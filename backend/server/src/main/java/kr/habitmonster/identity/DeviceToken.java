package kr.habitmonster.identity;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** {@code identity.device_token} — 푸시 알림(FCM)을 보낼 기기. 토큰 하나는 한 계정에만 묶인다. */
@Entity
@Table(schema = "identity", name = "device_token")
public class DeviceToken {

	public enum Platform { ANDROID, IOS }

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(name = "user_id", nullable = false)
	private Long userId;

	@Column(name = "fcm_token", nullable = false, unique = true, length = 255)
	private String fcmToken;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false)
	private Platform platform;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected DeviceToken() {
	}

	public DeviceToken(Long userId, String fcmToken, Platform platform, Instant now) {
		this.userId = userId;
		this.fcmToken = fcmToken;
		this.platform = platform;
		this.updatedAt = now;
	}

	public Long getUserId() {
		return userId;
	}

	/** 같은 기기에서 다른 계정으로 로그인하면 토큰을 그 계정으로 옮긴다 (API 명세: 같은 토큰이 다른 계정에 있으면 옮김). */
	public void assignTo(Long userId, Platform platform, Instant now) {
		this.userId = userId;
		this.platform = platform;
		this.updatedAt = now;
	}
}
