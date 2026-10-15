package kr.habitmonster.auth;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Locale;

import kr.habitmonster.auth.AuthDtos.LoginResponse;
import kr.habitmonster.auth.AuthDtos.MeView;
import kr.habitmonster.auth.AuthDtos.TokenResponse;
import kr.habitmonster.auth.social.SocialIdentity;
import kr.habitmonster.auth.social.SocialVerifier;
import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.identity.AuthCredential;
import kr.habitmonster.identity.AuthCredentialRepository;
import kr.habitmonster.identity.AuthProvider;
import kr.habitmonster.identity.DeviceToken;
import kr.habitmonster.identity.DeviceTokenRepository;
import kr.habitmonster.identity.RefreshTokenRepository;
import kr.habitmonster.identity.User;
import kr.habitmonster.identity.UserRepository;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 회원 · 로그인 (API 명세 v5 "1. 회원 · 설정").
 *
 * <p>계정 규칙: 이메일 하나에 계정 하나 (DB v1.7 {@code users.email} 유일). 이메일 가입과 소셜 가입이 같은 이메일이어도
 * 자동으로 합치지 않고 409 {@code EMAIL_REGISTERED_WITH_OTHER_METHOD}로 원래 가입 방법을 알려 준다.
 * 이메일 가입은 이메일 인증이 없어서, 자동으로 합치면 남의 이메일로 먼저 가입해 두는 방식으로 계정을 빼앗을 수 있기 때문이다.
 */
@Service
public class AuthService {

	private final UserRepository users;
	private final AuthCredentialRepository credentials;
	private final RefreshTokenRepository refreshTokens;
	private final DeviceTokenRepository deviceTokens;
	private final TokenService tokens;
	private final PasswordEncoder passwordEncoder;
	private final List<SocialVerifier> verifiers;
	private final List<WithdrawalStep> withdrawalSteps;
	private final Clock clock;
	/** 없는 이메일로 로그인해도 비밀번호 검사 시간을 똑같이 써서, 응답 시간으로 가입 여부를 알 수 없게. */
	private final String dummyHash;

	public AuthService(UserRepository users, AuthCredentialRepository credentials, RefreshTokenRepository refreshTokens,
			DeviceTokenRepository deviceTokens, TokenService tokens, PasswordEncoder passwordEncoder,
			List<SocialVerifier> verifiers, List<WithdrawalStep> withdrawalSteps, Clock clock) {
		this.users = users;
		this.credentials = credentials;
		this.refreshTokens = refreshTokens;
		this.deviceTokens = deviceTokens;
		this.tokens = tokens;
		this.passwordEncoder = passwordEncoder;
		this.verifiers = verifiers;
		this.withdrawalSteps = withdrawalSteps;
		this.clock = clock;
		this.dummyHash = passwordEncoder.encode("dummy-password-for-timing");
	}

	@Transactional
	public LoginResponse signUp(String email, String password) {
		String e = AuthRules.requireValidEmail(email);
		AuthRules.requireValidPassword(password);
		users.findByEmail(e).ifPresent(owner -> rejectTakenEmail(owner, AuthProvider.EMAIL));
		Instant now = clock.instant();
		try {
			User user = users.saveAndFlush(new User(e, now));
			credentials.saveAndFlush(AuthCredential.email(user, e, passwordEncoder.encode(password), now));
			return respond(user, null);
		}
		catch (DataIntegrityViolationException race) { // 같은 이메일 동시 가입
			throw new ApiException(ErrorCode.EMAIL_TAKEN);
		}
	}

	@Transactional
	public LoginResponse login(String email, String password) {
		String e = AuthRules.normalizeEmail(email);
		AuthCredential cred = credentials.findByProviderAndProviderSubject(AuthProvider.EMAIL, e).orElse(null);
		String pw = password == null ? "" : password;
		if (cred == null) {
			passwordEncoder.matches(pw, dummyHash);
			throw new ApiException(ErrorCode.INVALID_CREDENTIALS);
		}
		if (!passwordEncoder.matches(pw, cred.getPasswordHash())) {
			throw new ApiException(ErrorCode.INVALID_CREDENTIALS);
		}
		return loginWith(cred, null);
	}

	/**
	 * 소셜 로그인. 토큰은 서버가 직접 검증하고, 처음 보는 사용자면 자동 가입.
	 * 제공자가 **검증한** 이메일만 계정 이메일로 쓴다 (결정 C4) — 검증 안 된 이메일로 남의 이메일 계정을 막는 일을 피하려고.
	 */
	@Transactional
	public LoginResponse social(String providerPath, String providerToken) {
		AuthProvider provider = AuthProvider.social(providerPath)
			.orElseThrow(() -> new ApiException(ErrorCode.UNSUPPORTED_PROVIDER));
		SocialVerifier verifier = verifiers.stream().filter(v -> v.provider() == provider).findFirst()
			.orElseThrow(() -> new ApiException(ErrorCode.UNSUPPORTED_PROVIDER));
		if (providerToken == null || providerToken.isBlank()) {
			throw new ApiException(ErrorCode.INVALID_PROVIDER_TOKEN);
		}
		SocialIdentity id = verifier.verify(providerToken);
		AuthCredential cred = credentials.findByProviderAndProviderSubject(provider, id.subject()).orElse(null);
		if (cred != null) {
			return loginWith(cred, false);
		}
		String email = id.verifiedEmail();
		if (email != null) {
			users.findByEmail(email).ifPresent(owner -> rejectTakenEmail(owner, provider));
		}
		Instant now = clock.instant();
		try {
			User user = users.saveAndFlush(new User(email, now));
			credentials.saveAndFlush(AuthCredential.social(user, provider, id.subject(), now));
			return respond(user, true);
		}
		catch (DataIntegrityViolationException race) { // 첫 로그인 버튼 두 번 · 같은 이메일 동시 가입
			throw new ApiException(ErrorCode.REQUEST_IN_PROGRESS);
		}
	}

	@Transactional(noRollbackFor = ApiException.class)
	public TokenResponse refresh(String refreshToken) {
		User user = tokens.rotate(refreshToken);
		TokenService.Tokens t = tokens.issue(user);
		return new TokenResponse(t.accessToken(), t.refreshToken());
	}

	@Transactional
	public void logout(String refreshToken) {
		tokens.revoke(refreshToken);
	}

	@Transactional(readOnly = true)
	public MeView me(Long userId) {
		User user = activeUser(userId);
		AuthCredential cred = credentials.findFirstByUser_IdOrderByIdAsc(userId)
			.orElseThrow(() -> new ApiException(ErrorCode.INVALID_TOKEN));
		return new MeView(user.getId(), user.getEmail(), cred.getProvider().name(), user.isOnboardingDone());
	}

	/** 예전 온보딩 완료 API ({@code PATCH /me/onboarding}). 3단계에서 {@code POST /onboarding}이 생기면 지운다. */
	@Transactional
	public MeView completeOnboarding(Long userId) {
		activeUser(userId).completeOnboarding(clock.instant());
		return me(userId);
	}

	/**
	 * 회원 탈퇴. 사용자 행은 남기고(DB 원칙 7) 상태를 WITHDRAWN으로, 이메일은 비운다.
	 * 로그인 수단 · refresh 토큰 · 푸시 토큰은 지우고, 다른 모듈 데이터는 각 {@link WithdrawalStep}이 정리한다.
	 * 아직 남아 있는 access 토큰은 {@code UserGateFilter}가 다음 요청부터 막는다.
	 */
	@Transactional
	public void withdraw(Long userId) {
		User user = activeUser(userId);
		withdrawalSteps.forEach(step -> step.onWithdraw(userId));
		deviceTokens.deleteByUserId(userId);
		refreshTokens.deleteAllForUser(userId);
		credentials.deleteByUser_Id(userId);
		user.withdraw(clock.instant());
	}

	/** 푸시 토큰 등록. 같은 토큰이 다른 계정에 있으면 이 계정으로 옮긴다 (한 기기 = 마지막 로그인 계정). */
	@Transactional
	public void registerDeviceToken(Long userId, String fcmToken, String platform) {
		if (fcmToken == null || fcmToken.isBlank() || fcmToken.length() > 255) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		DeviceToken.Platform p = parsePlatform(platform);
		Instant now = clock.instant();
		deviceTokens.findByFcmToken(fcmToken).ifPresentOrElse(
			t -> t.assignTo(userId, p, now),
			() -> deviceTokens.save(new DeviceToken(userId, fcmToken, p, now)));
	}

	/** 푸시 토큰 해제 — 로그아웃할 때 앱이 부른다 (결정 A5). 없거나 남의 토큰이면 조용히 성공. */
	@Transactional
	public void unregisterDeviceToken(Long userId, String fcmToken) {
		if (fcmToken != null) {
			deviceTokens.deleteByUserIdAndFcmToken(userId, fcmToken);
		}
	}

	private static DeviceToken.Platform parsePlatform(String platform) {
		try {
			return DeviceToken.Platform.valueOf(platform == null ? "" : platform.toUpperCase(Locale.ROOT));
		}
		catch (IllegalArgumentException e) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
	}

	/**
	 * 이미 쓰이는 이메일. 같은 방법으로 가입돼 있으면 EMAIL_TAKEN,
	 * 다른 방법이면 EMAIL_REGISTERED_WITH_OTHER_METHOD + 원래 가입 방법 (그 방법으로 로그인하라고 안내).
	 */
	private void rejectTakenEmail(User owner, AuthProvider requested) {
		AuthProvider p = credentials.findFirstByUser_IdOrderByIdAsc(owner.getId())
			.map(AuthCredential::getProvider).orElse(AuthProvider.EMAIL);
		if (p == requested) {
			throw new ApiException(ErrorCode.EMAIL_TAKEN);
		}
		String name = switch (p) {
			case KAKAO -> "카카오";
			case GOOGLE -> "구글";
			case EMAIL -> "이메일";
		};
		throw ApiException.registeredWithOtherMethod(p.name().toLowerCase(Locale.ROOT),
				name + "로 가입된 이메일이에요. " + name + "로 로그인해 주세요");
	}

	private User activeUser(Long userId) {
		User user = users.findById(userId).orElseThrow(() -> new ApiException(ErrorCode.INVALID_TOKEN));
		if (user.isWithdrawn()) {
			throw new ApiException(ErrorCode.INVALID_TOKEN);
		}
		return user;
	}

	private LoginResponse loginWith(AuthCredential cred, Boolean isNewUser) {
		User user = cred.getUser();
		if (user.isWithdrawn()) {
			throw new ApiException(ErrorCode.ACCOUNT_WITHDRAWN);
		}
		cred.touchLogin(clock.instant());
		return respond(user, isNewUser);
	}

	private LoginResponse respond(User user, Boolean isNewUser) {
		TokenService.Tokens t = tokens.issue(user);
		return new LoginResponse(t.accessToken(), t.refreshToken(), user.isOnboardingDone(), isNewUser);
	}
}
