package kr.habitmonster.idempotency;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

/**
 * {@code identity.idempotency_record} — 중복 방지 키 하나의 처리 결과.
 * 읽고 쓰기는 {@link IdempotencyStore}(SQL)가 하고, 이 클래스는 local 프로필(H2)에서 테이블을 만들기 위한 정의다.
 * PostgreSQL은 {@code backend/db/server_additions.sql}이 기준.
 */
@Entity
@Table(schema = "identity", name = "idempotency_record",
	uniqueConstraints = @UniqueConstraint(name = "uq_idempotency_record",
		columnNames = { "user_id", "method", "path", "idem_key" }))
class IdempotencyRecord {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(name = "user_id", nullable = false)
	private Long userId;

	@Column(nullable = false, length = 10)
	private String method;

	@Column(nullable = false, length = 500)
	private String path;

	@Column(name = "idem_key", nullable = false)
	private UUID idemKey;

	@Column(name = "request_hash", nullable = false, length = 64)
	private String requestHash;

	/** {@code PENDING}(아직 결과 없음) | {@code COMPLETED}(결과 저장됨) */
	@Column(nullable = false, length = 10)
	private String status;

	@Column(name = "response_status")
	private Integer responseStatus;

	@Column(name = "response_type", length = 100)
	private String responseType;

	@Column(name = "response_body", length = 1_000_000)
	private String responseBody;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "expires_at", nullable = false)
	private Instant expiresAt;

	protected IdempotencyRecord() {
	}
}
