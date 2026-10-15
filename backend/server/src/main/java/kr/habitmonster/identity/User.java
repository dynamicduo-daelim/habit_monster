package kr.habitmonster.identity;

import java.time.Instant;
import java.time.LocalDate;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** {@code identity.users} */
@Entity
@Table(schema = "identity", name = "users")
public class User {

	public enum Status { ACTIVE, WITHDRAWN }

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(length = 30)
	private String nickname;

	/** 온보딩을 끝낸 시각. 끝내기 전엔 null (DB v1.5: 단계 컬럼 없이 마지막에 한 번만 저장). */
	@Column(name = "onboarded_at")
	private Instant onboardedAt;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false)
	private Status status = Status.ACTIVE;

	@Column(name = "last_active_date")
	private LocalDate lastActiveDate;

	@Column(name = "frozen_at")
	private Instant frozenAt;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	@Column(name = "withdrawn_at")
	private Instant withdrawnAt;

	protected User() {
	}

	public User(Instant now) {
		this.createdAt = now;
		this.updatedAt = now;
	}

	public Long getId() {
		return id;
	}

	public String getNickname() {
		return nickname;
	}

	public Instant getOnboardedAt() {
		return onboardedAt;
	}

	public boolean isOnboardingDone() {
		return onboardedAt != null;
	}

	public boolean isWithdrawn() {
		return status == Status.WITHDRAWN;
	}

	/** 온보딩 완료. 이미 끝냈으면 처음 시각을 그대로 둔다. */
	public void completeOnboarding(Instant now) {
		if (onboardedAt != null) {
			return;
		}
		this.onboardedAt = now;
		this.updatedAt = now;
	}
}
