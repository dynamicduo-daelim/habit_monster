package kr.habitmonster.auth.social;

/**
 * 검증된 소셜 사용자.
 *
 * @param subject 제공자의 사용자 ID (카카오 회원번호, 구글 sub) → {@code auth_credential.provider_subject}
 * @param email 제공자가 준 이메일 (없을 수 있음)
 * @param emailVerified 제공자가 "이 이메일은 본인 것"이라고 확인했는지. 확인 안 된 이메일은 계정 이메일로 쓰지 않는다 (결정 C4)
 */
public record SocialIdentity(String subject, String email, boolean emailVerified) {

	/** 계정에 저장해도 되는 이메일 (검증된 것만, 소문자). */
	public String verifiedEmail() {
		return emailVerified && email != null && !email.isBlank() ? email.trim().toLowerCase(java.util.Locale.ROOT) : null;
	}
}
