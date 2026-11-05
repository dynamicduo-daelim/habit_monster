package kr.habitmonster.ai;

import java.util.List;
import java.util.regex.Pattern;

/**
 * 위기 신호 서버 키워드 검사 (명세 v6 5장 검사 7, 제안서 3차 목록). AI 판단과 따로 하고, 둘 중 하나라도 걸리면 {@code safety}.
 * AI가 실패한 대본형 응답에서도 검사한다.
 *
 * <ul>
 * <li><b>강한 표현만</b> 넣는다. "죽겠"("피곤해 죽겠어") · "못살겠"("더워서 못 살겠다") · "목매"("돈에 목매다") · "죽을래"는 일상 표현이라 뺐다</li>
 * <li>공백 · 문장부호를 지운 뒤 부분 일치 — "죽고 싶어" · "죽고싶다"가 같게</li>
 * <li>알고 받아들인 오탐: "자살 예방 영상 봤어"처럼 다른 뜻으로 써도 걸린다 (걸리면 게임 연출만 멈추고 기록 · 보상은 그대로)</li>
 * <li>미묘한 표현은 AI 판단에 맡긴다 — 이 목록은 보조 수단이다</li>
 * </ul>
 */
public final class SafetyKeywords {

	private SafetyKeywords() {
	}

	static final List<String> KEYWORDS = List.of(
		// 자살 · 죽음을 바람
		"자살", "극단적선택", "극단선택", "죽고싶", "죽고시퍼", "죽고십", "뒤지고싶", "디지고싶", "죽어버리고싶", "죽어야겠",
		"죽는게낫", "죽는게나을", "차라리죽",
		// 사라지고 싶음
		"사라지고싶", "없어지고싶", "태어나지말", "안태어났으면",
		// 삶을 거부함
		"살기싫", "살고싶지않", "사는게싫", "살아서뭐해", "살이유가없", "살의미가없",
		// 자해 · 방법
		"자해", "손목긋", "손목을긋", "목매달", "뛰어내리고싶", "투신", "약먹고죽",
		// 작별
		"유서");

	/** 공백 · 문장부호 · 기호 (한글 · 영문 · 숫자만 남긴다). */
	private static final Pattern NOT_WORD = Pattern.compile("[^\\p{IsHangul}\\p{IsAlphabetic}\\p{IsDigit}]");

	public static boolean flagged(String message) {
		if (message == null) {
			return false;
		}
		String s = NOT_WORD.matcher(message).replaceAll("");
		return KEYWORDS.stream().anyMatch(s::contains);
	}
}
