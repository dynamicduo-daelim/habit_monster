package kr.habitmonster.monster;

import java.util.random.RandomGenerator;

import org.springframework.stereotype.Component;

/**
 * 탐색 · 포획의 랜덤은 모두 여기서 나온다 — 테스트가 이 빈을 바꿔 결과를 고정한다 ({@code @MockitoBean Dice}).
 * 한 번 굴릴 때마다 0 이상 1 미만의 수.
 */
@Component
public class Dice {

	private final RandomGenerator random = RandomGenerator.getDefault();

	public double roll() {
		return random.nextDouble();
	}
}
