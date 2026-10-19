package kr.habitmonster.identity;

import java.time.Instant;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserRepository extends JpaRepository<User, Long> {

	/** 이메일(소문자)로 계정 찾기 — 이메일 하나에 계정 하나 (DB v1.7). */
	Optional<User> findByEmail(String email);

	/**
	 * 온보딩 완료 시각을 찍는다 — 아직 안 끝낸 사용자만. 바뀐 행 수(0이면 이미 끝냄).
	 * UPDATE 한 문장이라, 같은 사용자의 온보딩 두 건이 동시에 와도 하나만 1을 받는다 (나머지는 행 잠금을 기다린 뒤 0).
	 */
	@Modifying(clearAutomatically = true)
	@Query("update User u set u.onboardedAt = :now, u.updatedAt = :now where u.id = :id and u.onboardedAt is null")
	int markOnboarded(@Param("id") Long id, @Param("now") Instant now);
}
