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
import jakarta.persistence.UniqueConstraint;

/** {@code identity.users} */
@Entity
@Table(schema = "identity", name = "users",
	uniqueConstraints = @UniqueConstraint(name = "uq_users_email", columnNames = "email"))
public class User {

	public enum Status { ACTIVE, WITHDRAWN }

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(length = 30)
	private String nickname;

	/**
	 * 계정의 이메일 — 가입 방법과 관계없이 한 계정에만 (DB v1.7 {@code uq_users_email}). 소문자로 저장.
	 * 카카오처럼 이메일을 안 주거나 검증되지 않은 이메일이면 null. 탈퇴하면 비워서 같은 이메일로 다시 가입할 수 있게 한다.
	 */
	@Column(length = 255)
	private String email;

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

	/** @param email 소문자로 정규화한 이메일, 없으면 null */
	public User(String email, Instant now) {
		this.email = email;
		this.createdAt = now;
		this.updatedAt = now;
	}

	public Long getId() {
		return id;
	}

	public String getNickname() {
		return nickname;
	}

	public String getEmail() {
		return email;
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

	/** 탈퇴 — 행은 지우지 않고(DB 원칙 7) 상태만 바꾸고, 이메일은 비운다 (같은 이메일로 다시 가입 가능). */
	public void withdraw(Instant now) {
		this.status = Status.WITHDRAWN;
		this.withdrawnAt = now;
		this.email = null;
		this.nickname = null;
		this.updatedAt = now;
	}
}
