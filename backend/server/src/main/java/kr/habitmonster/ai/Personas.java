package kr.habitmonster.ai;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.Map;
import java.util.Optional;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

/**
 * 몬스터 28종의 성격 (기획 {@code docs/기획/2026-11-15-몬스터-대화.md} A). 내용은 성수연 님 캐릭터 설정서
 * ({@code 2026-11-03-캐릭터-이름-스토리.md} 1부 표)에서 이름 칸만 빼고 가져왔다 — 이름은 지금 DB 이름을 쓴다.
 *
 * <p>해석 · 대사 · 자유 대화 프롬프트의 첫 부분({@link #intro})을 만든다. 성격은 "어떤 아이인지", 호감도 단계는 "얼마나 친한지".
 * 자료는 {@code resources/ai/personas.json} (종 코드 → 성격). 종이 없으면(새 종을 시드에만 추가) 성격 없이 기본 말투.
 */
@Component
public class Personas {

	/** {@code speech}: 말버릇 · 말투, {@code habit}: 이어진 습관. */
	public record Persona(String personality, String speech, String likes, String habit) {
	}

	private final Map<String, Persona> byCode;

	Personas(JsonMapper json) {
		try (InputStream in = new ClassPathResource("ai/personas.json").getInputStream()) {
			this.byCode = Map.copyOf(json.readValue(in, new TypeReference<Map<String, Persona>>() {
			}));
		}
		catch (IOException e) {
			throw new UncheckedIOException("ai/personas.json을 읽지 못함", e);
		}
	}

	public Optional<Persona> of(String speciesCode) {
		return Optional.ofNullable(speciesCode == null ? null : byCode.get(speciesCode));
	}

	int size() {
		return byCode.size();
	}

	/** 프롬프트 첫 부분: 누구인지 + 성격 + 말투(호감도). 대화 상대가 없으면 "루틴몬"과 보통 말투. */
	String intro(CheckinInterpreter.Partner partner) {
		String name = partner == null ? "루틴몬" : partner.name();
		StringBuilder sb = new StringBuilder();
		sb.append("너는 습관 앱 '모아루틴'에 사는 몬스터 '").append(name).append("'야.\n");
		of(partner == null ? null : partner.speciesCode()).ifPresent(p -> sb
			.append("성격: ").append(p.personality()).append('\n')
			.append("말버릇: ").append(p.speech()).append(" — 가끔만 쓴다. 매 문장마다 붙이지 않는다.\n")
			.append("좋아하는 것: ").append(p.likes()).append('\n')
			.append("너와 이어진 습관: ").append(p.habit()).append('\n'));
		sb.append(CheckinInterpreter.tone(partner == null ? "MID" : partner.affectionTier())).append('\n');
		return sb.toString();
	}
}
