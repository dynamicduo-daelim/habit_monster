package kr.habitmonster.auth;

import java.time.Clock;
import java.time.Instant;
import java.util.List;

import kr.habitmonster.auth.AuthDtos.AuthResponse;
import kr.habitmonster.auth.AuthDtos.UserView;
import kr.habitmonster.auth.social.SocialIdentity;
import kr.habitmonster.auth.social.SocialVerifier;
import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.identity.AuthCredential;
import kr.habitmonster.identity.AuthCredentialRepository;
import kr.habitmonster.identity.AuthProvider;
import kr.habitmonster.identity.User;
import kr.habitmonster.identity.UserRepository;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

	private final UserRepository users;
	private final AuthCredentialRepository credentials;
	private final TokenService tokens;
	private final PasswordEncoder passwordEncoder;
	private final List<SocialVerifier> verifiers;
	private final Clock clock;
	/** 없는 이메일로 로그인해도 비밀번호 검사 시간을 똑같이 써서, 응답 시간으로 가입 여부를 알 수 없게. */
	private final String dummyHash;

	public AuthService(UserRepository users, AuthCredentialRepository credentials, TokenService tokens,
			PasswordEncoder passwordEncoder, List<SocialVerifier> verifiers, Clock clock) {
		this.users = users;
		this.credentials = credentials;
		this.tokens = tokens;
		this.passwordEncoder = passwordEncoder;
		this.verifiers = verifiers;
		this.clock = clock;
		this.dummyHash = passwordEncoder.encode("dummy-password-for-timing");
	}

	@Transactional
	public AuthResponse signUp(String email, String password) {
		String e = AuthRules.requireValidEmail(email);
		AuthRules.requireValidPassword(password);
		if (credentials.findByProviderAndProviderSubject(AuthProvider.EMAIL, e).isPresent()) {
			throw new ApiException(ErrorCode.EMAIL_TAKEN);
		}
		Instant now = clock.instant();
		User user = users.save(new User(now));
		try {
			credentials.saveAndFlush(AuthCredential.email(user, e, passwordEncoder.encode(password), now));
		}
		catch (DataIntegrityViolationException race) { // 같은 이메일 동시 가입
			throw new ApiException(ErrorCode.EMAIL_TAKEN);
		}
		return respond(user, AuthProvider.EMAIL, e);
	}

	@Transactional
	public AuthResponse login(String email, String password) {
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
		return loginWith(cred);
	}

	/** 소셜 로그인. 토큰은 서버가 직접 검증하고, 처음 보는 사용자면 자동 가입 (같은 이메일의 다른 계정과 합치지 않음 — Q-20). */
	@Transactional
	public AuthResponse social(String providerPath, String token) {
		AuthProvider provider = AuthProvider.social(providerPath)
			.orElseThrow(() -> new ApiException(ErrorCode.UNSUPPORTED_PROVIDER));
		SocialVerifier verifier = verifiers.stream().filter(v -> v.provider() == provider).findFirst()
			.orElseThrow(() -> new ApiException(ErrorCode.UNSUPPORTED_PROVIDER));
		if (token == null || token.isBlank()) {
			throw new ApiException(ErrorCode.INVALID_TOKEN);
		}
		SocialIdentity id = verifier.verify(token);
		AuthCredential cred = credentials.findByProviderAndProviderSubject(provider, id.subject()).orElse(null);
		if (cred != null) {
			return loginWith(cred);
		}
		Instant now = clock.instant();
		User user = users.save(new User(now));
		try {
			credentials.saveAndFlush(AuthCredential.social(user, provider, id.subject(), id.email(), now));
		}
		catch (DataIntegrityViolationException race) { // 첫 로그인 버튼 두 번
			throw new ApiException(ErrorCode.BAD_REQUEST, "잠시 후 다시 시도해 주세요");
		}
		return respond(user, provider, id.email());
	}

	@Transactional(noRollbackFor = ApiException.class)
	public AuthResponse refresh(String refreshToken) {
		User user = tokens.rotate(refreshToken);
		AuthCredential cred = credentials.findFirstByUser_IdOrderByIdAsc(user.getId())
			.orElseThrow(() -> new ApiException(ErrorCode.INVALID_TOKEN));
		return respond(user, cred.getProvider(), cred.getEmail());
	}

	@Transactional
	public void logout(String refreshToken) {
		tokens.revoke(refreshToken);
	}

	@Transactional(readOnly = true)
	public UserView me(Long userId) {
		User user = activeUser(userId);
		AuthCredential cred = credentials.findFirstByUser_IdOrderByIdAsc(userId)
			.orElseThrow(() -> new ApiException(ErrorCode.INVALID_TOKEN));
		return UserView.of(user, cred.getProvider(), cred.getEmail());
	}

	@Transactional
	public UserView completeOnboarding(Long userId) {
		activeUser(userId).completeOnboarding(clock.instant());
		return me(userId);
	}

	private User activeUser(Long userId) {
		User user = users.findById(userId).orElseThrow(() -> new ApiException(ErrorCode.INVALID_TOKEN));
		if (user.isWithdrawn()) {
			throw new ApiException(ErrorCode.INVALID_TOKEN);
		}
		return user;
	}

	private AuthResponse loginWith(AuthCredential cred) {
		User user = cred.getUser();
		if (user.isWithdrawn()) {
			throw new ApiException(ErrorCode.ACCOUNT_WITHDRAWN);
		}
		cred.touchLogin(clock.instant());
		return respond(user, cred.getProvider(), cred.getEmail());
	}

	private AuthResponse respond(User user, AuthProvider provider, String email) {
		TokenService.Tokens t = tokens.issue(user);
		return new AuthResponse(t.accessToken(), t.refreshToken(), UserView.of(user, provider, email));
	}
}
