package kr.habitmonster.identity;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<User, Long> {

	/** 이메일(소문자)로 계정 찾기 — 이메일 하나에 계정 하나 (DB v1.7). */
	Optional<User> findByEmail(String email);
}
