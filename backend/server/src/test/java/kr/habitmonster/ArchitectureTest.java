package kr.habitmonster;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.lang.ArchCondition;
import com.tngtech.archunit.lang.ConditionEvents;
import com.tngtech.archunit.lang.SimpleConditionEvent;

import jakarta.persistence.Table;

import org.junit.jupiter.api.Test;

/**
 * 모듈 규칙 검사 (DB 원칙 1 · 3, 결정 D-33): **서버 패키지 = DB 스키마**이고, 각 모듈은 자기 스키마 테이블만 읽고 쓴다.
 * 다른 모듈의 데이터가 필요하면 그 모듈의 서비스를 부른다. 이 규칙이 지켜져야 나중에 모듈을 따로 떼어 낼 수 있고,
 * "골드는 지갑 서비스만 바꾼다" 같은 약속을 코드가 보장한다.
 *
 * <ol>
 * <li>저장소({@code *Repository})는 자기 모듈 안에서만 쓴다 (ArchUnit — 클래스 사이의 의존을 바이트코드로 본다).</li>
 * <li>JPA 엔티티의 {@code @Table(schema)}는 그 스키마의 패키지에 둔다.</li>
 * <li>SQL 문자열에 나오는 {@code 스키마.테이블}은 그 패키지의 스키마뿐이다 (소스 파일의 문자열을 직접 읽어 검사).</li>
 * </ol>
 */
class ArchitectureTest {

	static final String ROOT = "kr.habitmonster";

	/** 패키지 → 그 패키지가 다룰 수 있는 DB 스키마. 여기 없는 패키지(onboarding · home · common …)는 SQL을 쓰지 않는다. */
	static final Map<String, String> SCHEMA_OF = Map.of(
		"identity", "identity", "auth", "identity", // auth = 회원 모듈의 서비스 · 컨트롤러
		"habit", "habit", "goal", "goal", "wallet", "wallet", "shop", "shop", "monster", "monster",
		"config", "config", "idempotency", "api", "ai", "ai");

	static final Pattern TABLE_REF = Pattern.compile("\\b(identity|habit|goal|wallet|shop|monster|config|ai|api)\\.([a-z_]+)\\b");

	static final JavaClasses CLASSES = new ClassFileImporter()
		.withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
		.importPackages(ROOT);

	@Test
	void 저장소는_자기_모듈_안에서만_쓴다() {
		for (String module : List.of("habit", "goal", "wallet", "shop", "monster", "idempotency", "ai")) {
			classes().that().resideInAPackage(ROOT + "." + module + "..").and().haveSimpleNameEndingWith("Repository")
				.should().onlyHaveDependentClassesThat().resideInAPackage(ROOT + "." + module + "..")
				.allowEmptyShould(true)
				.check(CLASSES);
		}
		// 회원 저장소는 회원 서비스(auth)와 사용자 검사 필터(config.UserGateFilter · SecurityConfig)까지
		classes().that().resideInAPackage(ROOT + ".identity..").and().haveSimpleNameEndingWith("Repository")
			.should().onlyHaveDependentClassesThat()
			.resideInAnyPackage(ROOT + ".identity..", ROOT + ".auth..", ROOT + ".config..")
			.check(CLASSES);
	}

	@Test
	void 엔티티는_자기_스키마의_패키지에_있다() {
		classes().that().areAnnotatedWith(Table.class)
			.should(new ArchCondition<>("@Table(schema)의 패키지에 있다") {
				@Override
				public void check(JavaClass c, ConditionEvents events) {
					String schema = c.getAnnotationOfType(Table.class).schema();
					String pkg = c.getPackageName().substring(ROOT.length() + 1).split("\\.")[0];
					boolean ok = schema.equals(SCHEMA_OF.get(pkg));
					events.add(new SimpleConditionEvent(c, ok, c.getName() + " → schema " + schema));
				}
			})
			.check(CLASSES);
	}

	@Test
	void SQL은_자기_스키마의_테이블만_쓴다() throws IOException {
		Path src = Path.of("src/main/java/kr/habitmonster");
		List<String> violations = new ArrayList<>();
		try (Stream<Path> files = Files.walk(src)) {
			for (Path file : files.filter(f -> f.toString().endsWith(".java")).toList()) {
				Path rel = src.relativize(file);
				String pkg = rel.getNameCount() > 1 ? rel.getName(0).toString() : "";
				String own = SCHEMA_OF.get(pkg);
				for (String literal : stringLiterals(Files.readString(file))) {
					Matcher m = TABLE_REF.matcher(literal);
					while (m.find()) {
						if (!m.group(1).equals(own)) {
							violations.add(rel + ": " + m.group());
						}
					}
				}
			}
		}
		assertThat(violations).as("다른 모듈의 테이블은 그 모듈의 서비스로").isEmpty();
	}

	/** 소스의 문자열 상수(텍스트 블록 포함)만 꺼낸다 — 주석의 "habit.habit_user" 같은 설명은 검사하지 않으려고. */
	static List<String> stringLiterals(String source) {
		List<String> out = new ArrayList<>();
		Matcher m = Pattern.compile("\"\"\"(.*?)\"\"\"|\"((?:[^\"\\\\\\n]|\\\\.)*)\"", Pattern.DOTALL).matcher(stripComments(source));
		while (m.find()) {
			out.add(m.group(1) != null ? m.group(1) : m.group(2));
		}
		return out;
	}

	private static String stripComments(String source) {
		return source.replaceAll("(?s)/\\*.*?\\*/", "").replaceAll("(?m)^\\s*//.*$", "");
	}
}
