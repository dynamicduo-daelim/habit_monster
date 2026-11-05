package kr.habitmonster.ai;

import java.time.LocalDate;

import kr.habitmonster.config.BalanceConfig;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 하루 AI 해석 호출 한도 {@code ai_daily_call_limit} (명세 v6 5장). DB에 세서 서버를 다시 켜도 유지된다
 * (예전엔 서버 메모리라 다시 켜면 처음부터였다). 모델을 부르기 <b>전에</b> 센다.
 */
@Service
public class AiCallLimit {

	private final CallCountRepository counts;
	private final BalanceConfig config;

	AiCallLimit(CallCountRepository counts, BalanceConfig config) {
		this.counts = counts;
		this.config = config;
	}

	/** 오늘 호출을 하나 쓴다. 한도에 이미 닿았으면 false (세지 않음). 짧은 트랜잭션 하나 — 모델 호출 동안 DB를 잡지 않는다. */
	@Transactional
	public boolean tryUse(long userId, LocalDate day) {
		return counts.tryIncrement(userId, day, config.aiDailyCallLimit());
	}
}
