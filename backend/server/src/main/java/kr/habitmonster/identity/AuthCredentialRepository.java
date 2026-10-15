package kr.habitmonster.identity;

import java.util.Optional;

import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AuthCredentialRepository extends JpaRepository<AuthCredential, Long> {

	@EntityGraph(attributePaths = "user")
	Optional<AuthCredential> findByProviderAndProviderSubject(AuthProvider provider, String providerSubject);

	/** 사용자의 로그인 수단 (계정 연결 기능이 없어 하나). */
	Optional<AuthCredential> findFirstByUser_IdOrderByIdAsc(Long userId);

	void deleteByUser_Id(Long userId);
}
