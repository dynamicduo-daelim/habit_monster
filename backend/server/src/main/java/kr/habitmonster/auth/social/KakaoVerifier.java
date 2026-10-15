package kr.habitmonster.auth.social;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.AuthProperties;
import kr.habitmonster.identity.AuthProvider;

import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * 카카오: 앱이 보낸 access token으로
 * 1) {@code /v1/user/access_token_info} → 우리 앱(app_id)에서 발급된 토큰인지 확인
 * 2) {@code /v2/user/me} → 회원번호 · 이메일.
 */
@Component
public class KakaoVerifier implements SocialVerifier {

	@JsonIgnoreProperties(ignoreUnknown = true)
	record TokenInfo(Long id, @JsonProperty("app_id") Long appId) {
	}

	@JsonIgnoreProperties(ignoreUnknown = true)
	record Account(String email,
			@JsonProperty("is_email_valid") Boolean emailValid,
			@JsonProperty("is_email_verified") Boolean emailVerified) {

		boolean verified() {
			return Boolean.TRUE.equals(emailValid) && Boolean.TRUE.equals(emailVerified);
		}
	}

	@JsonIgnoreProperties(ignoreUnknown = true)
	record Me(Long id, @JsonProperty("kakao_account") Account account) {
	}

	private final RestClient client = RestClient.create("https://kapi.kakao.com");
	private final String appId;

	public KakaoVerifier(AuthProperties props) {
		this.appId = props.kakao().appId();
	}

	@Override
	public AuthProvider provider() {
		return AuthProvider.KAKAO;
	}

	@Override
	public SocialIdentity verify(String token) {
		if (appId == null || appId.isBlank()) {
			throw new ApiException(ErrorCode.SOCIAL_NOT_CONFIGURED);
		}
		try {
			TokenInfo info = client.get().uri("/v1/user/access_token_info")
				.header("Authorization", "Bearer " + token)
				.retrieve().body(TokenInfo.class);
			if (info == null || info.appId() == null || !appId.equals(String.valueOf(info.appId()))) {
				throw new ApiException(ErrorCode.INVALID_PROVIDER_TOKEN);
			}
			Me me = client.get().uri("/v2/user/me")
				.header("Authorization", "Bearer " + token)
				.retrieve().body(Me.class);
			if (me == null || me.id() == null || !me.id().equals(info.id())) {
				throw new ApiException(ErrorCode.INVALID_PROVIDER_TOKEN);
			}
			Account a = me.account();
			return new SocialIdentity(String.valueOf(me.id()), a == null ? null : a.email(), a != null && a.verified());
		}
		catch (RestClientException e) {
			throw new ApiException(ErrorCode.INVALID_PROVIDER_TOKEN);
		}
	}
}
