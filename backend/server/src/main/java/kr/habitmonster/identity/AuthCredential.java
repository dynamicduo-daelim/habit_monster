package kr.habitmonster.identity;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

/**
 * {@code identity.auth_credential} — 로그인 수단 하나.
 * EMAIL이면 providerSubject = 소문자 이메일 + passwordHash(BCrypt), 소셜이면 providerSubject = 제공자의 사용자 ID.
 * 이메일 자체는 {@link User#getEmail()} (DB v1.7: 계정당 하나, 이 테이블의 email 컬럼은 삭제됨).
 */
@Entity
@Table(schema = "identity", name = "auth_credential", uniqueConstraints = {
		@UniqueConstraint(name = "uq_auth_provider_subject", columnNames = { "provider", "provider_subject" }),
		@UniqueConstraint(name = "uq_auth_user_provider", columnNames = { "user_id", "provider" }) })
public class AuthCredential {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "user_id")
	private User user;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false)
	private AuthProvider provider;

	@Column(name = "provider_subject", nullable = false, length = 255)
	private String providerSubject;

	@Column(name = "password_hash", length = 100)
	private String passwordHash;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "last_login_at")
	private Instant lastLoginAt;

	protected AuthCredential() {
	}

	public static AuthCredential email(User user, String normalizedEmail, String passwordHash, Instant now) {
		AuthCredential c = new AuthCredential();
		c.user = user;
		c.provider = AuthProvider.EMAIL;
		c.providerSubject = normalizedEmail;
		c.passwordHash = passwordHash;
		c.createdAt = now;
		c.lastLoginAt = now;
		return c;
	}

	public static AuthCredential social(User user, AuthProvider provider, String subject, Instant now) {
		AuthCredential c = new AuthCredential();
		c.user = user;
		c.provider = provider;
		c.providerSubject = subject;
		c.createdAt = now;
		c.lastLoginAt = now;
		return c;
	}

	public User getUser() {
		return user;
	}

	public AuthProvider getProvider() {
		return provider;
	}

	public String getPasswordHash() {
		return passwordHash;
	}

	public void touchLogin(Instant now) {
		this.lastLoginAt = now;
	}
}
