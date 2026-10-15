package kr.habitmonster.idempotency;

import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.dao.DataAccessException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * {@code api.idempotency_record}(DB v1.7 공식 테이블) 읽기 · 쓰기. 잠금(FOR UPDATE NOWAIT)을 써야 해서 JPA 대신 SQL로 둔다.
 *
 * <p>공식 테이블은 처리 중(IN_PROGRESS)에 {@code locked_until}(처리 기한)을 요구한다. 우리는 "처리 중"의 진짜 판단을
 * 행 잠금으로 하고(D-17), 기한은 제약을 지키고 운영자가 볼 수 있게 채워 둔다.
 */
@Component
class IdempotencyStore {

	/** 키 보관 기간 (API 명세 v4: 24시간). */
	static final Duration TTL = Duration.ofHours(24);

	/** 처리 기한 (DB config {@code idempotency_lock_seconds} = 30). 표시용 — 실제 판단은 행 잠금. */
	static final Duration LOCK = Duration.ofSeconds(30);

	record Scope(long userId, String method, String path, UUID key) {
	}

	record Saved(String requestHash, boolean completed, Integer status, String body) {
	}

	private final JdbcTemplate jdbc;
	private final Clock clock;
	private final TransactionTemplate newTx;
	/** 응답 본문 자리표시자. PostgreSQL 컬럼은 JSONB라 형 변환이 필요하고, H2(테스트) 테이블은 문자열이다. */
	private final String jsonParam;

	IdempotencyStore(JdbcTemplate jdbc, Clock clock, PlatformTransactionManager txm) {
		this.jdbc = jdbc;
		this.clock = clock;
		this.newTx = new TransactionTemplate(txm);
		this.newTx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
		String db = jdbc.execute((ConnectionCallback<String>) c -> c.getMetaData().getDatabaseProductName());
		this.jsonParam = "PostgreSQL".equalsIgnoreCase(db) ? "cast(? as jsonb)" : "?";
	}

	/**
	 * 키 행이 있게 만든다 (따로 커밋 — 동시에 온 같은 키 요청이 이 행을 보고 잠금을 다투게).
	 * 보관 기간이 지난 행은 새 요청으로 덮어쓴다.
	 */
	void prepare(Scope s, String requestHash) {
		Instant now = clock.instant();
		newTx.executeWithoutResult(tx -> {
			int reset = jdbc.update("""
				update api.idempotency_record
				   set request_hash = ?, status = 'IN_PROGRESS', locked_until = ?, response_status = null,
				       response_body = null, completed_at = null, created_at = ?, expires_at = ?
				 where user_id = ? and http_method = ? and request_path = ? and idempotency_key = ? and expires_at <= ?""",
				requestHash, ts(now.plus(LOCK)), ts(now), ts(now.plus(TTL)),
				s.userId(), s.method(), s.path(), s.key(), ts(now));
			if (reset > 0) {
				return;
			}
			try {
				jdbc.update("""
					insert into api.idempotency_record
					  (user_id, http_method, request_path, idempotency_key, request_hash, status, locked_until,
					   created_at, expires_at)
					values (?, ?, ?, ?, ?, 'IN_PROGRESS', ?, ?, ?)""",
					s.userId(), s.method(), s.path(), s.key(), requestHash, ts(now.plus(LOCK)), ts(now), ts(now.plus(TTL)));
			}
			catch (DuplicateKeyException alreadyThere) {
				// 같은 키가 이미 있음 — 그 행으로 진행
			}
		});
	}

	/**
	 * 지금 트랜잭션에서 키 행을 잠근다. 다른 요청이 같은 키를 처리 중이면 기다리지 않고 바로 실패한다
	 * ({@link KeyBusyException} → 409 {@code REQUEST_IN_PROGRESS}).
	 * 처리 중에 서버가 죽으면 DB 연결이 끊기면서 잠금이 풀려 같은 키로 다시 보낼 수 있다.
	 */
	Optional<Saved> lock(Scope s) {
		try {
			return selectForUpdate(s);
		}
		catch (DataAccessException e) {
			if (isLockFailure(e)) {
				throw new KeyBusyException();
			}
			throw e;
		}
	}

	/**
	 * "다른 요청이 잠그고 있음"인지. PostgreSQL은 SQL 상태 55P03(lock_not_available)인데 Spring이 잠금 예외로 바꿔 주지 않아
	 * (UncategorizedSQLException) 상태 코드로 직접 본다. H2(테스트)는 잠금 시간 초과(QueryTimeoutException)로 알려 준다.
	 */
	private static boolean isLockFailure(DataAccessException e) {
		if (e instanceof PessimisticLockingFailureException || e instanceof QueryTimeoutException) {
			return true;
		}
		for (Throwable t = e; t != null; t = t.getCause()) {
			if (t instanceof SQLException sql && "55P03".equals(sql.getSQLState())) {
				return true;
			}
		}
		return false;
	}

	private Optional<Saved> selectForUpdate(Scope s) {
		return jdbc.query("""
			select request_hash, status, response_status, response_body
			  from api.idempotency_record
			 where user_id = ? and http_method = ? and request_path = ? and idempotency_key = ?
			   for update nowait""",
			(rs, i) -> new Saved(rs.getString(1), "COMPLETED".equals(rs.getString(2)),
				rs.getObject(3) == null ? null : rs.getInt(3), rs.getString(4)),
			s.userId(), s.method(), s.path(), s.key()).stream().findFirst();
	}

	/** 결과 저장. 지금 트랜잭션에서 (2xx — 비즈니스 변경과 같이 커밋). */
	void complete(Scope s, int status, String body) {
		jdbc.update("""
			update api.idempotency_record
			   set status = 'COMPLETED', locked_until = null, response_status = ?, response_body = %s, completed_at = ?
			 where user_id = ? and http_method = ? and request_path = ? and idempotency_key = ? and status = 'IN_PROGRESS'"""
			.formatted(jsonParam),
			status, body == null || body.isBlank() ? null : body, ts(clock.instant()),
			s.userId(), s.method(), s.path(), s.key());
	}

	/** 결과 저장. 새 트랜잭션에서 (4xx — 비즈니스 변경은 되돌린 뒤 결과만 남김). */
	void completeInNewTx(Scope s, int status, String body) {
		newTx.executeWithoutResult(tx -> complete(s, status, body));
	}

	/** 보관 기간이 지난 키 정리 (매일 04:30). */
	@Scheduled(cron = "0 30 4 * * *", zone = "Asia/Seoul")
	void deleteExpired() {
		jdbc.update("delete from api.idempotency_record where expires_at <= ?", ts(clock.instant()));
	}

	/** 같은 키를 다른 요청이 잠그고 처리 중. */
	static final class KeyBusyException extends RuntimeException {

		KeyBusyException() {
			super(null, null, false, false);
		}
	}

	private static Timestamp ts(Instant i) {
		return Timestamp.from(i);
	}
}
