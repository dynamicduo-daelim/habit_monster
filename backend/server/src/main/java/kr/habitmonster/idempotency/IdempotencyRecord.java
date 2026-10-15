package kr.habitmonster.idempotency;

import java.io.Serializable;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

/**
 * {@code api.idempotency_record} — 중복 방지 키 하나의 처리 결과 (DB v1.7 공식 테이블).
 * 읽고 쓰기는 {@link IdempotencyStore}(SQL)가 하고, 이 클래스는 local 프로필(H2)에서 같은 모양의 테이블을 만들기 위한 정의다.
 * PostgreSQL에서는 공식 {@code schema.sql}이 기준 (JSONB · CHECK 제약은 그쪽에만 있다).
 */
@Entity
@Table(schema = "api", name = "idempotency_record")
class IdempotencyRecord {

	@Embeddable
	record Key(@Column(name = "user_id") Long userId,
			@Column(name = "http_method", length = 10) String httpMethod,
			@Column(name = "request_path", length = 255) String requestPath,
			@Column(name = "idempotency_key") UUID idempotencyKey) implements Serializable {
	}

	@EmbeddedId
	private Key id;

	@Column(name = "request_hash", nullable = false, length = 64)
	private String requestHash;

	/** {@code IN_PROGRESS} | {@code COMPLETED} */
	@Column(nullable = false, length = 20)
	private String status;

	@Column(name = "locked_until")
	private Instant lockedUntil;

	@Column(name = "response_status")
	private Integer responseStatus;

	/** PostgreSQL은 JSONB. H2에서는 문자열로 둔다. */
	@Column(name = "response_body", length = 1_000_000)
	private String responseBody;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "completed_at")
	private Instant completedAt;

	@Column(name = "expires_at", nullable = false)
	private Instant expiresAt;

	protected IdempotencyRecord() {
	}
}
