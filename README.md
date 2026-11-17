# TailQuestions (꼬리질문)

Claude 데스크톱 앱 옆에 붙어 다니는 **꼬리질문 패널**이에요.

Claude와 대화하다 보면 곁가지 질문이 생기는데, 그걸 본 대화에 물으면 흐름이 섞여요.
TailQuestions를 쓰면 **같은 대화 맥락을 아는 Claude에게 옆 패널에서 따로** 물어볼 수 있어요.
답은 패널에만 남고, 본 대화는 깨끗하게 유지돼요.

git 브랜치처럼 생각하면 돼요. 메인 대화가 `main`이고, main의 각 질문(커밋)에서 여러 가지를 쳐서 따로 물어요.

```
● 네이버 인턴 공고 설명해줘          ← main 질문
│  ↳ 정답지는 누가 만들어?           ← 가지
│  ↳ 정밀도 vs 재현율 예시 더
● 지원서에 뭘 강조하면 좋을까?
│  ↳ AST 정적 분석이 뭐야?
```

```
┌──── Claude 데스크톱 ─────────┐┌─ 꼬리질문 ────────────┐
│                              ││ ● main 질문             │
│  ...정답 데이터셋 구축...     ││ ❝ 선택한 부분           │
│   ▲ 드래그 후 ⌥⇧Space         ││ ───────────────────── │
│                              ││ 나: 정답지는 누가 만들어? │
│                              ││ Claude: ...             │
└──────────────────────────────┘└───────────────────────┘
```

---

## 필요한 것

- macOS 14 이상
- Xcode Command Line Tools (`xcode-select --install`). Xcode 전체는 필요 없어요.
- [Claude Code](https://claude.com/claude-code)가 설치되어 있고 로그인된 상태
  → 지금 쓰는 **Claude 유료 구독(Pro/Max)으로 답해요. API 키나 추가 요금이 필요 없어요.**
  (Claude Code가 없다면 설정에서 Anthropic API 키 방식을 쓸 수도 있어요.)

## 설치 (처음 한 번)

```bash
git clone https://github.com/lyemee/TailQuestions.git
cd TailQuestions
./scripts/setup-signing.sh          # 1. 로컬 서명 인증서 만들기 (한 번만)
./scripts/build-app.sh --install    # 2. 빌드 → ~/Applications 에 설치 → 실행
```

실행하면 꼬리질문 패널이 뜨고, 메뉴바 오른쪽 위에 **↳ 아이콘**이 생겨요.

### 3. 손쉬운 사용 권한 켜기

Claude 화면의 대화와 드래그한 텍스트를 읽으려면 꼭 필요해요.

1. 시스템 설정 → 개인정보 보호 및 보안 → **손쉬운 사용**
2. **+** 를 눌러 `~/Applications/TailQuestions.app` 을 추가하고 켜기
   (Finder에서 `⌘⇧G` → `~/Applications` 입력하면 찾을 수 있어요)
3. 패널 위의 주황색 경고가 사라지면 완료

> `setup-signing.sh` 로 만든 인증서로 서명하기 때문에, 나중에 다시 빌드해도 권한을 다시 켤 필요가 없어요.

### 4. 로그인 시 자동 실행 켜기 (추천)

패널의 ⚙️ 설정 → **"Mac에 로그인하면 자동으로 실행"** 을 켜요.
허용을 요청하면 시스템 설정 → 일반 → 로그인 항목에서 TailQuestions를 허용해 주세요.

---

## 사용법

| 하고 싶은 것 | 방법 |
|---|---|
| 답변 일부에 대해 꼬리질문 | Claude 앱에서 텍스트를 **드래그 → ⌥⇧Space** (Option+Shift+Space) |
| main 질문 목록과 가지 보기 | 아무것도 선택하지 않고 **⌥⇧Space** |
| 특정 질문에서 가지 치기 | 트리에서 그 질문 아래 **"여기서 가지 치기"** |
| 그냥 바로 질문 | 트리 화면 아래 입력칸에 입력 (지금 대화 전체가 맥락으로 들어가요) |
| 꼬리의 꼬리질문 | 가지 화면 아래 입력칸에 이어서 입력 |
| 트리로 돌아가기 | 왼쪽 위 **‹ main** |
| 가지 삭제 | 트리에서 가지를 **우클릭 → 가지 삭제** |
| 패널 닫기 | 패널을 보는 중에 **⌥⇧Space** 다시 누르기, 또는 창 닫기 |

- 입력: **Return** 으로 보내기, **⌥Return** 으로 줄바꿈
- 📌 핀: Claude 창 오른쪽에 붙어 다니기 켜기/끄기 (화면이 좁으면 Claude 창 오른쪽 안쪽에 겹쳐 붙어요)
- 🕘 기록: 다른 대화의 가지들까지 대화별로 다시 보기
- ⚙️ 설정: 연결 방식(구독 / API 키), 모델, 자동 실행, 권한 상태
- 메뉴바 ↳ 아이콘: 패널 열기, 설정, 종료

---

## 계속 쓰기

### 업데이트

```bash
cd TailQuestions
git pull
./scripts/build-app.sh --install   # 실행 중인 앱을 끄고 새 버전으로 바꿔서 다시 실행
```

### 데이터 위치

| 내용 | 위치 |
|---|---|
| 가지(꼬리질문) 기록 | `~/Library/Application Support/TailQuestions/threads.json` |
| 진단 로그 (대화 내용 없이 길이·개수만) | `~/Library/Application Support/TailQuestions/debug.log` |
| API 키 (API 키 방식일 때만) | 키체인 `com.lyemee.TailQuestions` |

### 문제 해결

| 증상 | 해결 |
|---|---|
| ⌥⇧Space 를 눌러도 아무 일이 없음 | 메뉴바에 ↳ 아이콘이 있는지 확인 (없으면 `open ~/Applications/TailQuestions.app`). `debug.log` 에 `hotkey register status=0` 이 아니면 다른 앱이 같은 단축키를 쓰는 중 |
| 주황색 "권한이 없어요" 경고 | 손쉬운 사용 목록에서 TailQuestions를 **−** 로 지우고 다시 **+** 로 추가 |
| "로그인되어 있지 않아요" 오류 | 터미널에서 `claude` 실행 후 로그인 |
| "사용 한도에 도달" 오류 | 구독 사용량 한도예요. 잠시 후 다시 시도 |
| 트리에 "질문을 구분하지 못했어요" | Claude 앱 화면 구조가 바뀐 경우예요. 질문은 되지만 맥락이 한 덩어리로 들어가요. 이슈로 알려주세요 |

### 삭제

```bash
pkill -x TailQuestions
rm -rf ~/Applications/TailQuestions.app ~/Library/Application\ Support/TailQuestions
security delete-certificate -c "TailQuestions Local Signing"   # 서명 인증서도 지우려면
```

손쉬운 사용·로그인 항목 목록에서도 TailQuestions를 지워 주세요.

---

## 작동 방식

1. ⌥⇧Space 를 누르면 macOS **손쉬운 사용(Accessibility) API**로 Claude 앱 화면의 대화 전체와 선택한 텍스트를 읽어요.
2. 대화 전체(main)를 맥락으로, 선택한 부분과 질문을 함께 Claude에게 보내요.
   Claude는 그 대화를 이어서 하는 것처럼 답하지만, 답은 패널에만 남아요.
3. 연결 방식은 두 가지예요 (설정에서 선택).
   - **Claude 구독 (기본값)**: 설치된 Claude Code CLI(`claude -p`)로 질문해요.
     로그인된 구독을 그대로 써서 추가 요금이 없고, 구독 사용량에서 차감돼요.
     도구·설정·MCP 서버는 모두 끈 채로 실행되고, Claude Code 기록에도 남지 않아요.
   - **Anthropic API 키**: API를 직접 호출해요. 구독과 별도로 사용량만큼 요금이 나가요.

### 한계

- 화면에 보이는 텍스트만 맥락으로 넘어가요 (첨부 파일, 이미지, 프로젝트 자료, 메모리는 제외).
- 질문/답변 구분은 Claude 화면의 CSS 클래스(`font-user-message`, `font-claude-response`)에 의존해요.
  구분에 실패하면 화면 전체 텍스트를 한 덩어리로 보내요.
- 구독 방식은 질문마다 Claude Code를 새로 실행해서 답이 시작되기까지 몇 초 걸려요.
- 가지에서 또 가지를 치는 중첩 가지는 아직 없어요.

## 코드 구조

| 파일 | 역할 |
|---|---|
| `AppDelegate.swift` | 메뉴바 아이콘, 전역 단축키, 단축키를 눌렀을 때의 흐름 |
| `AXReader.swift` | Claude 앱 화면에서 선택한 텍스트, 대화 내용, 창 위치 읽기 |
| `PanelController.swift` | Claude 창 옆에 붙는 플로팅 패널 |
| `ClaudeCodeClient.swift` | Claude Code CLI로 구독을 써서 질문 (기본값) |
| `ClaudeClient.swift` | Anthropic Messages API 스트리밍 호출 (API 키 방식) |
| `AppModel.swift` | 가지 상태, main-가지 트리 구성, 저장, 프롬프트 구성, 자동 실행 |
| `Views.swift` | SwiftUI 화면 |
| `HotKey.swift` / `Keychain.swift` / `DebugLog.swift` | 전역 단축키 / API 키 저장 / 진단 로그 |
| `scripts/setup-signing.sh` | 로컬 서명 인증서 생성 (권한 유지용) |
| `scripts/build-app.sh` | `.app` 빌드, 서명, 설치 |
