package kr.habitmonster.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;

/** 게임 수치를 DB 시드(config.balance_config)에서 읽는다. */
class BalanceConfigTest extends PostgresTest {

	@Autowired
	BalanceConfig config;

	@Autowired
	JsonMapper json;

	@Test
	void 시드의_수치를_타입대로_읽는다() {
		assertThat(config.fieldMax()).isEqualTo(5);
		assertThat(config.starterAffection()).isEqualTo(3);
		assertThat(config.exploreMissRate()).isEqualTo(0.35);
		assertThat(config.captureRate()).isEqualTo(Map.of(1, 0.8, 2, 0.6, 3, 0.4));
		assertThat(config.exploreRarityWeight()).containsEntry(1, 60).containsEntry(3, 10);
		assertThat(config.periodMultiplier()).containsEntry("D30", 1.5);
		assertThat(config.periodDays()).containsEntry("D100", 100);
		assertThat(config.evolveLevels()).containsExactly(10, 20);
		assertThat(config.dexUnlockThresholds()).containsExactly(5, 10, 15);
	}

	@Test
	void 진화_단계와_호감도_단계() {
		assertThat(config.stageOf(9)).isZero();
		assertThat(config.stageOf(10)).isEqualTo(1);
		assertThat(config.stageOf(20)).isEqualTo(2);
		assertThat(config.nextEvolutionLevel(7)).isEqualTo(10);
		assertThat(config.nextEvolutionLevel(20)).isNull();
		assertThat(config.affectionTier(3)).isEqualTo("LOW");
		assertThat(config.affectionTier(4)).isEqualTo("MID");
		assertThat(config.affectionTier(7)).isEqualTo("HIGH");
	}

	@Test
	void 시드의_모든_키는_서버가_읽거나_안_쓴다고_적어_둔_것() {
		Set<String> unknown = new TreeSet<>(config.keys());
		unknown.removeAll(BalanceConfig.REQUIRED);
		unknown.removeAll(BalanceConfig.NOT_USED_BY_SERVER);
		assertThat(unknown).as("새 설정 키 — BalanceConfig.REQUIRED 또는 NOT_USED_BY_SERVER에 넣기").isEmpty();
	}

	@Test
	void 필요한_키가_없으면_서버가_뜨지_않는다() {
		Map<String, JsonNode> values = new HashMap<>();
		jdbc.query("select key, value::text from config.balance_config",
				rs -> { values.put(rs.getString(1), json.readTree(rs.getString(2))); });
		values.remove("field_max");

		assertThatThrownBy(() -> new BalanceConfig(values))
			.isInstanceOf(IllegalStateException.class)
			.hasMessageContaining("field_max");
	}
}
