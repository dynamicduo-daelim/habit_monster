package kr.habitmonster.identity;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceTokenRepository extends JpaRepository<DeviceToken, Long> {

	Optional<DeviceToken> findByFcmToken(String fcmToken);

	void deleteByUserIdAndFcmToken(Long userId, String fcmToken);

	void deleteByUserId(Long userId);
}
