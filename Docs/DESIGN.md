<!--
  @file        DESIGN.md
  @description SpectaDockPin 설계서 v1 — 여러 모니터를 쓰는 Mac에서 Dock을 한 화면(기본: 주 화면)에 고정하는
               메뉴바 앱. Dock을 부르는 이벤트만 골라 막고, Dock 위치를 직접 확인해 필요할 때만 되돌린다.
               출시 예정 없음. 샌드박스 없이 Developer ID로 서명하고 공증해서 직접 쓴다.
  @author      Kennt Kim
  @company     Calida Lab
  @created     2026-10-18
  @lastUpdated 2026-10-18
-->

# SpectaDockPin — 설계서 v1

> 계기(2026-10-18): Dock이 보조 모니터로 자꾸 넘어간다. 공개된 고정 앱 세 개(DockAnchor, DockAnchor-2.0,
> dock-cleat)를 코드로 읽어 보니 모두 결함이 있다. 원본 DockAnchor는 PR과 이슈를 처리하지 않고 있다.
> Kennt 결정: **직접 만든다.** 처음 이름은 SiliconDockPin이었고, 같은 날 앱 스토어 출시를 정하면서 **SpectaDockPin**으로 바꿨다(Specta 제품군, §13).
> 같은 날 다시 결정: **출시 예정 없음.** 앱 스토어와 샌드박스를 버리고, Developer ID 서명 + 공증 빌드로 직접 쓴다(§9, §13 결정 2). 샌드박스 실측(S1–S8)은 기록으로 남긴다.
>
> 이 문서의 사실은 같은 날 Kennt의 Mac에서 실험해서 확인한 것이다(§3). 확인하지 못한 것은 "검증 필요"로 따로 적었다.

| | SpectaDockPin |
|---|---|
| 한 줄 | **Dock을 부르는 순간만 막고, Dock이 어디 있는지 직접 확인해 필요할 때만 되돌리는 메뉴바 앱** |
| 플랫폼 | macOS 14+ (개발·실측은 macOS 27.0, Apple Silicon) |
| 배포 | **출시 예정 없음.** 샌드박스 없음, Developer ID 서명 + 공증(§9). Kennt 결정(2026-10-18): "그냥 출시 예정 없음으로 하자, 서명 공증으로 처리" |
| 권한 | 손쉬운 사용 하나. macOS 27에서는 이 화면 이름이 **"Device Control and Data Access"**다. 화면 녹화는 필요 없다(§3 F7) |
| 규약 | Specta 시리즈 코드 규약(§7). 가장 가까운 선례는 SpectArk(`SpectaBackup`)다. 샌드박스 없는 Developer ID 앱이라는 점도 같다 |

---

## 1. 목표와 범위

목표:
1. Dock이 고정 화면 밖으로 넘어가지 않는다. 마우스 이동과 드래그 모두.
2. 그래도 넘어가 있으면(잠자기, 화면 연결 변화, 앱이 꺼져 있던 동안) 알아채고, 안전한 때에만 되돌린다.
3. 되돌린 뒤 실제로 돌아왔는지 확인한다. 실패하면 실패라고 보여 준다.
4. 사용자의 다른 동작(보조 화면 아래쪽 클릭과 호버, 핫 코너, 드래그 앤 드롭)은 건드리지 않는다.

범위 밖:
- Dock을 왼쪽이나 오른쪽에 두는 배치. 이때 Dock은 바깥쪽 끝 화면에 붙고, 화면을 넘나드는 규칙이 다르다. 앱은 이 배치를 감지하면 쉬고 이유를 표시한다(§5.6).
- Cmd+Tab 전환기 위치. 시스템 동작이라 건드리지 않는다. macOS 27부터는 Dock이 아니라 활성 창이 있는 화면에 뜬다(DockLock 이슈 #11, 개발자 확인).
- Dock을 여러 화면에 동시에 띄우기. macOS는 Dock을 한 번에 한 화면에만 보여 준다.

---

## 2. 기존 앱 검토 (2026-10-18)

세 앱은 원리가 같다. 고정 화면이 아닌 모니터 아래쪽 띠에서 마우스 이벤트를 가로챈다.

| 앱 | 판단 | 근거 |
|---|---|---|
| aitiotekt/dock-cleat | 쓰지 않음 | 좌표 뒤집기에 주 화면 높이 대신 가장 높은 화면 높이를 써서, 위아래 배치에서 엉뚱한 곳을 막는다(이슈 #1). 0.5초마다 AppleScript로 Dock 설정을 묻는다 |
| galacticdave/DockAnchor-2.0 | 쓰지 않음 | 시스템이 탭을 끄면 다시 켜지 않는다. 서명과 공증이 없다. 기준 화면 기본값이 주 화면이 아니라 내장 화면이다 |
| bwya77/DockAnchor 2.1.0 | 참고만 함 | 탭 재활성화와 `CGDisplayBounds` 좌표는 맞다. 그러나 `mouseMoved`만 막아 드래그로 넘어가고(#30), 아래 10px 띠를 통째로 막는다. 되돌릴 때 Dock 위치를 확인하지 않고 깨어날 때마다 커서를 움직이며(#39), 결과도 확인하지 않는다(#37). 6월 이후 PR(#32, #37)과 이슈에 반응이 없다 |
| DockLock Lite/Plus (상용, 앱 스토어) | 참고만 함 | 샌드박스 앱이고 구현은 공개되지 않았다(GitHub `JulyIghor/DockLockPro`에는 README만 있음). 동작 조건(Dock 아래쪽, "디스플레이마다 별도의 Spaces" 켜짐)이 §3의 실측과 같다. 2026-10-18 사이트·FAQ·이슈 확인: **빌드 616부터 기본 잠금에 권한이 필요 없다.** 손쉬운 사용 권한은 "신뢰도 향상"과 깨어난 뒤 되돌리기, 명령으로 옮기기에만 쓴다. Lite의 핵심 잠금은 체험 뒤에도 무료이고, 수정 키(Shift, Cmd, Option, Ctrl) 일시 해제는 구독 기능이다. 숨은 설정(`jumpDelay`, `jumpNormalDistance 2.05`, `jumpHiddenDistance 5.05`)이 있고, `autohide-delay`를 0으로 바꾸면 잠금이 깨진다는 보고가 있다(이슈 #3, #5, #7). 시간에 기대는 방식으로 보이며, F17·F18의 권한 없는 밀어 올리기와 맞아떨어진다(추정). 그 밖의 보고: 보조 화면 전체 화면 앱(#6), Sidecar(#4), 잠금 해제 뒤 위치 초기화(#12), macOS 27 불안정(#13, #14) |

---

## 3. 실측 (2026-10-18, macOS 27.0)

환경: LG 3008×1692(주 화면, 가운데), 맥북 내장 1728×1117(왼쪽), Dell 2560×1440(오른쪽). 세 화면은 위쪽 끝이 맞춰져 있다.
Dock은 아래쪽에 있고, 자동 숨김은 꺼져 있다. 핫 코너는 오른쪽 아래(빠른 메모)뿐이다. "디스플레이마다 별도의 Spaces"는 켜져 있다.
좌표는 CG 전역 좌표다. 주 화면 왼쪽 위가 원점이고, 아래로 갈수록 y가 커진다.

실험 방법: `CGEvent`를 HID 단계(`.cghidEventTap`)에 16ms 간격으로 보내 실제 커서를 움직였다. Dock 위치는 Dock 창 범위로 읽었다.
매 실험 뒤에는 커서를 원래 자리로 돌려놓았다.

| # | 실험 | 결과 | 설계에 주는 뜻 |
|---|---|---|---|
| F1 | 보조 화면 **맨 아래 한 줄**(Dell y=1439, 맥북 y=1116)에 이벤트를 계속 보냄. 아래로 미는 값(deltaY)은 0 | 0.39–1.00초 만에 넘어감. 처음 한 번만 1.00초였고 나머지는 0.4초 안팎. LG로 돌아올 때는 0.33–0.56초 | 머무르기만 해도 넘어간다. 미는 동작은 필요 없다 |
| F2 | 같은 자리에서 1, 2, 4px 위 (Dell y=1438/1437/1435, 맥북 y=1115) | 2.5초 동안 그대로 | 트리거는 **맨 아래 1px 줄뿐**이다. 원본의 10px 띠는 필요 이상이다 |
| F3 | 맨 아래 줄에 이벤트를 **한 번만** 보내고 4초 기다림 | 그대로 | 이벤트가 계속 들어와야 반응한다. 커서가 그 자리에 있는 것만으로는 반응하지 않는다 |
| F4 | 세션 탭(`.cgSessionEventTap`, `.defaultTap`)이 맨 아래 줄 이벤트만 버림. 커서는 실제로 그 줄에 있음 | 3초, 4초 모두 그대로(이벤트 138개, 191개 모두 버림) | Dock은 커서 위치가 아니라 **전달된 이벤트**로 판단한다. 1px 줄만 막으면 충분하다 |
| F5 | Dell 오른쪽 아래 모서리 픽셀(5567,1439)에 머무름 / 1, 3, 7, 17, 27px 안쪽(5566…5540) | 모서리 픽셀만 그대로이고, 1px 안쪽부터는 모두 넘어감. **F23에서 뒤집힘** | 막는 범위는 줄 전체여야 한다. 모서리 픽셀을 통과시켜도 된다는 결론은 F23으로 철회 |
| F6 | 이벤트를 Dock 프로세스에만 보냄(`postToPid`). 커서는 그대로 | 4초, 3초 모두 그대로 | 커서를 움직이지 않고 되돌리는 방법은 **없다**(가설 기각). 되돌리기는 실제 커서가 필요하다 |
| F7 | 권한이 전혀 없는 앱 번들(LaunchServices로 실행)에서 창 목록 조회 | Dock PID와 레이어 20, 화면 범위는 읽힘. 창 이름은 nil. 소유 앱 이름("Dock")도 읽혔지만 이건 문서화되지 않은 동작이다 | Dock 창은 **PID + 레이어**로 찾는다. 화면 녹화 권한은 필요 없다 |
| F8 | Dock 창 범위 | Dock이 있는 화면의 범위와 정확히 같음(LG일 때 {0,0,3008,1692}, Dell일 때 {3008,0,2560,1440}). 창은 하나, 레이어 20 = `CGWindowLevelForKey(.dockWindow)` | Dock이 있는 화면을 추측 없이 알 수 있다 |
| F9 | 손쉬운 사용 권한 없이 `.defaultTap` 생성 | nil | 권한이 없으면 막을 수 없다. 권한 상태를 앱이 알고 있어야 한다 |
| F10 | 버튼을 누르지 않은 채 `leftMouseDragged`만 보냄 | 한 번은 몇 초 뒤 넘어갔고, 한 번은 6초 동안 그대로. 그 뒤 Dock이 드래그 중 상태에 갇혀 `mouseMoved`로 되돌아오지 않았다. `leftMouseUp` 하나를 보내자 풀렸다 | 합성 드래그는 판단 근거로 쓸 수 없다(T1에서 실제 드래그로 확인). **되돌리기는 드래그 이벤트를 절대 보내지 않고, 버튼이 눌려 있으면 기다린다** |
| F11 | 합성 이벤트로 오른쪽 아래 모서리에 다가감(막는 장치 없음) | 빠른 메모가 뜨지 않음 | 핫 코너는 합성 이벤트로 확인할 수 없다(T2) |
| F12 | 잠금 해제 상태의 `CGSessionCopyCurrentDictionary()` | `CGSSessionScreenIsLocked` 키 없음 | 잠겼을 때 이 키가 생기는지는 T4에서 확인한다 |
| F13 | 앱이 직접 `CGEvent.tapEnable(false)`로 탭을 끔(DockProbe, 전용 스레드 탭) | 콜백에 `tapDisabledByUserInput`이 한 번 들어온다 | 이 이벤트를 받으면 무조건 다시 켜는 코드는 **끄려던 탭을 되살린다**. EdgeGuard는 정리 중인지 확인한 뒤에만 다시 켠다(§5.2) |
| F14 | Dock 창 번호 하나로 `CGWindowListCreateDescriptionFromArray` 조회. 배열에는 CFNumber가 아니라 `CGWindowID` 값을 포인터로 넣는다(콜백 NULL) | 전체 목록과 같은 PID, 레이어, 범위가 나온다 | §5.3의 "창 하나만 조회"가 된다 |

**DockProbe 실측** (같은 날, `tools/DockProbe` + 5ms 창 기록기 + 권한 없는 샌드박스 앱 `NoPermProbe`):

회귀: F1(Dell 0.37–0.43초, 맥북 0.32초), F2(1px 위 2.5초 그대로), F4(201개 버림, 그대로)가 다시 맞았다.

| # | 실험 | 결과 | 설계에 주는 뜻 |
|---|---|---|---|
| F15 | 5ms 간격으로 Dock 소유 창 전체를 기록하며 Dock을 옮김 | 옮길 때마다 레이어 20 창이 **하나 더** 0.10–0.25초 생긴다("DockClone", 이전 화면 범위, 목록 맨 앞, 매번 새 창 번호). 그 사이에 새 프로세스가 전체 목록 첫 후보를 읽으면 이전 화면으로 잘못 판정한다(실제로 `home`이 "이미 LG"라고 잘못 판단) | 전체 목록 조회는 후보가 하나가 될 때까지 다시 읽는다(최대 1초). 샌드박스에서는 창 이름을 못 읽으므로(F7) 이름으로 거르지 않는다. 캐시한 창 번호(32)는 옮기는 중에도 새 범위를 맞게 보였다 |
| F16 | Dock이 있는 화면의 아래 끝, **Dock 아이콘 위**에서 2초 밀다가 커서를 이벤트 없이 순간 이동(warp)으로 빼고 되돌리기 | 고정 화면 맨 아래 **한 점에 바로 꽂는** 방식은 3/3 실패. 그대로 두면 75초 넘게 갇혀 있었다. 같은 상태에서 **40pt 위에서 3pt씩 내려오는** 방식은 6/6 성공(0.66–0.73초). 모서리(x=3008)에서 민 경우에는 한 점 방식도 3/3 성공. 위쪽에 이벤트 하나 찍기, deltaY만 주기, 줄을 따라 옆으로 움직이기로는 풀리지 않았다 | 포인터가 Dock 안에 있다가 이벤트 없이 사라지면 Dock이 한 점 트리거를 무시한다. 실제 마우스는 빠져나갈 때 이벤트가 생기므로 평소엔 없지만, Relocator는 커서를 warp로 복원하므로 해당된다. **Relocator는 항상 위에서 내려오며 다가간다**(§5.4) |
| F17 | 권한 없는 앱이 맨 아래 줄 이벤트를 보면 커서를 L pt 위로 warp하고, `push`(현재 커서에서 매번 s pt씩 아래로)로 밀기 | L=2, s=3: 매 이벤트가 다시 줄에 닿아 0.59초 만에 넘어감. L=5·10, s=3: 3.5초 그대로. L=20, s=10: 그대로. L=20, s=25: 넘어감. L=60, s=25: 그대로 | **줄 이벤트 사이에 줄 밖 이벤트가 하나라도 끼면 Dock의 대기 시간이 처음부터 다시 시작된다.** 밀어 올리는 거리가 한 이벤트의 이동량보다 크면 막힌다 |
| F18 | 권한을 받은 적 없는 샌드박스 앱(`ai.calidalab.scratch.nopermprobe`, Apple Development 서명) | AX, PostEvent, ListenEvent, 화면 녹화 모두 false. 그래도 `NSEvent` 전역 마우스 모니터가 이벤트를 받았고(177/178), `CGWarpMouseCursorPosition`이 됐다(58/58 위치 확인). `.listenOnly` 탭 생성도 nil이 아니었다(이벤트가 오는지는 확인하지 않음) | DockLock의 "권한 없이 기본 보호"(빌드 616)는 이 조합으로 설명된다(추정). 합성 이벤트로는 권한 없이 막을 수 있다. 실제 마우스에서는 warp 뒤 입력이 잠깐 억제되는 시스템 동작(기본 0.25초)이 있어 결과가 다를 수 있다 → T8 |
| F19 | 보조 화면 맨 아래 1pt를 덮는 투명 창(`ignoresMouseEvents = false`, 화면 보호기 레벨과 Dock+1 레벨) | 그 줄에 이벤트를 보내자 그대로 넘어갔다(0.47초, 0.38초) | Dock은 커서 아래 창과 상관없이 이벤트로 판단한다(F4와 같은 결론). **창으로는 막을 수 없다** |
| F20 | Dell, 맥북 각각에 실제 전체 화면 창을 띄움(창 크기로 확인) | 두 화면 모두 맨 아래 1px 줄에서만 넘어갔다(0.41초, 0.34초). 1, 5, 14px 위는 2.5초 동안 그대로. 고정 화면에 전체 화면이 있을 때 Dock 창은 `onscreen` false지만 범위는 그대로 읽혔다 | 전체 화면 앱이 있어도 막는 줄은 같다(DockLock 이슈 #6 상황). 위치 판정에 `onscreen`을 조건으로 쓰지 않는다 |
| F21 | Dock 자동 숨김을 켜고(`defaults` + `killall Dock`, 끝난 뒤 원래 값으로 복원) 측정 | 트리거는 그대로 맨 아래 1px(0.26초), 1–9px 위는 그대로. 모든 화면의 아래 여백이 0이고 Dock 창은 `onscreen` false. Dock을 재시작하자 PID(782→16415)와 창 번호(32→4114)가 바뀌었다 | T5는 합성 이벤트로 통과. 자동 숨김이면 방향을 알 수 없다(§5.6 예상과 같음). DockLocator는 PID와 창 번호가 바뀌는 경우를 처리한다 |
| F22 | 이벤트를 보낸 직후 커서 위치(`CGEvent(source: nil).location`) 읽기 | 이벤트 하나(약 16ms)만큼 이전 위치가 나올 때가 있다. 첫 이벤트 직후에는 아예 원래 위치가 나왔다 | 커서를 옮긴 결과를 확인하는 코드는 이 지연을 고려한다. `push`는 warp한 뒤 위치가 맞을 때까지 기다리고 시작한다 |
| F23 | 네 모서리 픽셀과 그 1px 안쪽에 머무름: Dell (5567,1439) (5566,1439) (3008,1439) (3009,1439), 맥북 (-1728,1116) (-1727,1116) (-1,1116) (-2,1116) | **8곳 모두 넘어감**(0.34–0.68초). Dell 오른쪽 아래 바깥 모서리도 0.68초 만에 넘어갔다 | F5와 다르다. F5가 왜 그대로였는지는 모른다(그때는 F16 같은 상태였을 수 있다). **모서리도 막는다.** 핫 코너가 모서리 이벤트를 필요로 하는지는 T2에서 실제 마우스로 본다 |

**실제 마우스 확인** (같은 날, Kennt 손, 앱이 막는 중, DockProbe `watch`로 기록):

| # | 확인 | 결과 |
|---|---|---|
| R1 (T3) | Dell, 맥북 아래 끝을 실제 마우스로 계속 밀기 | 4.16초 동안 맨 아래 줄 이벤트 351개를 버렸고, Dock은 그대로였다. 실제 마우스 y는 소수점 값이다(1439.1–1439.96 등). 한 이벤트 이동량은 최대 51pt였다(가속). F17의 밀어 올리기 방식이 실제 마우스로는 막기 어렵다는 근거다 |
| R2 (T1) | Finder 파일을 끌고 Dell 아래 끝에 머물기 | 드래그 이벤트 100개, 61개, 103개를 버렸고 넘어가지 않았다. 원본 DockAnchor #30 상황이 막힌다 |
| R3 (T2) | 막는 중에 오른쪽 아래 핫 코너(빠른 메모) | 작동했다(Kennt 확인). 모서리를 막아도 핫 코너는 살아 있다 → §13 결정 8 확정 |
| R4 | Option을 누른 채 Dell 아래 밀기, 이어서 메뉴의 Move Dock Back Now | Option 이벤트 60개가 통과해 Dock이 Dell로 갔고, 앱은 되돌리지 않았다. 메뉴로 0.41초 만에 돌아왔다 |
| R5 (T4) | Dock이 Dell에 있는 채 화면 잠금 → 해제 | 해제 뒤 LG로 돌아왔다(Kennt 확인) |

**샌드박스 실측** (같은 날, `com.apple.security.app-sandbox`만 켠 테스트 앱 `SandboxProbe`, Apple Development 서명, `/Applications`에 설치). 앱 스토어 계획을 접어서 지금은 기록용이다. 샌드박스가 없으면 S4의 Dock 설정 읽기가 되고, 나머지(S1–S3, S5–S8)는 그대로 적용된다:

| # | 실험 | 결과 | 설계에 주는 뜻 |
|---|---|---|---|
| S1 | 권한을 받은 샌드박스 앱이 `.defaultTap` 생성 + Dell 맨 아래 줄 이벤트 버리기 | 탭이 만들어졌고, 189개를 버렸고, Dock은 그대로였다. `AXIsProcessTrusted`, `CGPreflightPostEventAccess`, `CGPreflightListenEventAccess` 모두 true | **막기는 샌드박스에서 된다** |
| S2 | 샌드박스 앱이 HID 단계로 `mouseMoved`를 보내 Dell에 있던 Dock을 LG로 되돌림 | 0.47초 만에 돌아왔고, 커서도 복원됐다 | **되돌리기도 샌드박스에서 된다** |
| S3 | 샌드박스에서 Dock 창 조회 | PID, 레이어 20, 범위 모두 읽힘(F7과 같음) | DockLocator는 그대로 쓴다 |
| S4 | 샌드박스에서 `CFPreferencesCopyAppValue(…, "com.apple.dock")` | `orientation`, `autohide`, `wvous-*` 모두 nil | 샌드박스 안에서는 Dock 설정 파일을 못 읽는다. 지금 설계는 샌드박스가 없어 직접 읽는다(§5.6). 핫 코너 설정은 알 수 없다 |
| S5 | `NSScreen.screensHaveSeparateSpaces`(앱 컨텍스트, `NSApplication.shared` 이후) | true. `NSApplication` 없이 부르면 false가 나와서 틀린다 | Spaces 설정은 이 API로 읽는다. 앱이 시작된 뒤에 부른다 |
| S6 | `NSScreen.visibleFrame` | Dock이 있는 LG만 아래쪽이 49pt 들어가 있다. 메뉴 막대 높이는 화면과 시점마다 다르다(Dell 0 또는 30pt) | Dock 방향은 Dock이 있는 화면의 **아래, 왼쪽, 오른쪽 여백**으로만 판단한다. 위쪽 여백은 쓰지 않는다 |
| S7 | 권한 요청(`CGRequestPostEventAccess`) 뒤 시스템 설정 목록 | `/private/tmp`에 있는 앱은 TCC에 기록돼도 목록에 보이지 않는다. `/Applications`에 두고 +로 추가하자 보였다. 같은 인증서로 다시 빌드해도 권한이 유지됐다 | 개발 빌드도 `/Applications`(또는 보이는 위치)에 설치해서 시험한다. 서명은 계속 같은 인증서로 한다 |
| S8 | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` 열기 | macOS 27에서 "Device Control and Data Access" 화면이 열린다 | 온보딩은 이 URL로 해당 화면을 바로 연다. 화면 이름을 문구에 박아 넣지 않는다 |

앱 스토어 선례: 같은 일을 하는 DockLock Lite가 샌드박스 앱으로 앱 스토어에 있다(1.2.5부터 1.5.2까지 25번 넘게 업데이트, 마지막 2026-10-06). Kennt가 쓰는 Magnet도 앱 스토어 앱이면서 이 권한을 쓴다.

검색으로 확인한 것:
- **권한을 끄면 입력이 먹통이 될 수 있다.** `.defaultTap`이 켜진 상태에서 손쉬운 사용 권한을 끄면 키보드와 마우스 입력이 전부 멈추고, 재부팅해야 한다는 보고가 있다(Apple Developer Forums 844416, FB24619068). Sequoia, Tahoe, macOS 27에서 재현되고 해결되지 않았다. → I4, §5.7
- 듣기만 하는 탭(`.listenOnly`)은 입력 모니터링 권한, 막는 탭(`.defaultTap`)은 손쉬운 사용 권한이 필요하다(포럼 828052).
- 창 목록의 어떤 값이 권한 없이 채워지는지는 문서화되지 않았다(DTS, 포럼 839069). 그래서 이름이 아니라 PID와 레이어로 찾는다.
- 앱 스토어 심사: DTS는 PostEvent와 ListenEvent 권한이 샌드박스와 함께 쓸 수 있다고 했다(포럼 820594, 780626). 다만 심사 정책은 DTS가 답할 수 없다고 했다. `CGEvent.post`를 쓴 클립보드 앱이 2.4.5("손쉬운 사용 기능을 다른 용도로 사용")로 두 번 거절된 사례가 있다(포럼 820594, 129840). → §12

---

## 4. 불변식 (협상 대상이 아니다)

- **I1 최소 개입.** 막는 것은 고정 화면이 아닌 화면의 맨 아래 1px 줄로 들어오는 포인터 이동과 드래그 이벤트뿐이다. 다른 이벤트, 다른 위치는 손대지 않는다.
- **I2 확인 없이는 움직이지 않는다.** Dock이 고정 화면 밖에 있다고 확인됐을 때만 되돌린다. 되돌린 뒤에는 다시 확인하고, 확인되지 않으면 성공이라고 표시하지 않는다.
- **I3 사람이 있을 때만 커서를 움직인다.** 화면이 잠겨 있거나, 콘솔 세션이 아니거나(빠른 사용자 전환), 버튼이 눌려 있거나, 사용자가 커서를 움직이는 중이면 되돌리지 않고 기다린다.
- **I4 권한이 없으면 탭도 없다.** 손쉬운 사용 권한이 사라지는 신호가 오면 다른 일보다 먼저 탭을 끄고 제거한다.
- **I5 탭 콜백은 메인 스레드와 무관하다.** 전용 스레드의 런루프에서 돌고, 미리 계산한 사각형 몇 개와 비교만 한다. 메인 스레드가 멈춰도 시스템이 탭을 시간 초과로 끄지 않게 하기 위해서다.
- **I6 조건이 안 맞으면 쉬고 이유를 보여 준다.** 화면이 하나뿐일 때, Dock이 아래쪽이 아닐 때, Spaces가 화면을 가로지를 때, 권한이 없을 때가 해당한다.
- **I7 테스트 호스트는 아무것도 하지 않는다.** 단위 테스트 실행 중에는 탭을 만들지 않고 커서도 움직이지 않는다(SpectArk `AppRuntime.isUnitTestHost` 선례).
- **I8 네트워크와 텔레메트리가 없다.** 로그에는 좌표와 상태만 남긴다. 업데이트 장치도 없다(§9).

---

## 5. 아키텍처

```
            ┌──────────────── Main actor ─────────────────┐
 NSWorkspace│  AppModel (@Observable)  ◄── MenuBarView      │
 notifs ───►│    │  status, settings                        │
 CGDisplay  │    ├─ SessionMonitor  (wake, lock, space,     │
 reconfig ─►│    │                   display changes)       │
            │    ├─ PermissionWatch (AX trust)               │
            │    ├─ DockPreferences (orientation, spans)     │
            │    ├─ DisplayMap      (pure geometry)          │
            │    ├─ DockLocator     (where is the Dock?)     │
            │    └─ Relocator       (check → move → recheck) │
            └──────────────┬───────────────────────────────┘
                           │ GuardSnapshot (lock-protected)
            ┌──────────────▼───────────── "EdgeGuard" thread ┐
            │  EdgeGuard: CGEventTap (.cgSessionEventTap,     │
            │  .headInsertEventTap, .defaultTap) + CFRunLoop  │
            │  callback → EdgeRule.shouldDrop(...)  (pure)    │
            └─────────────────────────────────────────────────┘
```

### 5.1 DisplayMap (순수 계산)

- 입력: 화면 목록 `[DisplayInfo]`(`CGDirectDisplayID`, `CGDisplayCreateUUIDFromDisplayID`로 얻은 UUID, `CGDisplayBounds`, 주 화면 여부)과 고정 화면 설정.
- 출력:
  - `anchor`: 고정 화면. 설정한 UUID의 화면이 연결돼 있으면 그 화면이고, 아니면 주 화면(`CGMainDisplayID`)이다.
  - `triggerStrips: [CGRect]`: 막을 줄. 고정 화면이 아닌 화면마다 `y ∈ [maxY − 1, maxY)`인 1px 줄을 만든다. 그 화면 바로 아래에 다른 화면이 맞닿아 있는 x 구간은 뺀다. 그 구간은 Dock 트리거가 아니라 다음 화면으로 넘어가는 통로이기 때문이다.
  - `relocationPoint`: 고정 화면의 바깥쪽 아래 끝 가운데 점. 아래에 맞닿은 화면이 없는 가장 긴 구간의 가운데를 고르고, 모서리는 피한다.
- 좌표는 전부 CG 전역 좌표(F 표 기준)다. `NSScreen`(왼쪽 아래 원점) 좌표는 쓰지 않는다. dock-cleat의 버그가 이 둘을 섞은 데서 나왔다.
- 모서리 픽셀도 막는다. 모서리도 Dock을 옮기고(F23), 막아도 핫 코너는 작동한다(R3).
- 화면 구성이 바뀌면(`NSApplication.didChangeScreenParametersNotification`, 0.5초 디바운스) 다시 계산하고, `GuardSnapshot`을 통째로 교체한다. 이 알림은 연결, 해제, 해상도, 배치, 주 화면 변경을 모두 덮고 메인 스레드로 온다.
- Option으로 옮긴 상태(`userOverride`)에서는 Dock이 있는 화면의 줄도 막지 않는다. 자동 숨김이면 그 줄이 Dock을 꺼내는 길이기 때문이다.

### 5.2 EdgeGuard (전용 스레드)

- 탭: `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`. F4에서 이 조합으로 확인했다.
- 받는 이벤트: `mouseMoved`, `leftMouseDragged`, `rightMouseDragged`, `otherMouseDragged`, 그리고 `tapDisabledByTimeout`, `tapDisabledByUserInput`.
- 콜백은 `EdgeRule.shouldDrop(location:, snapshot:)` 한 번만 부른다. 위치가 `triggerStrips` 안에 있으면 nil을 돌려줘 이벤트를 버리고, 아니면 그대로 통과시킨다.
  - 앱이 직접 보낸 이벤트(§5.4)는 `eventSourceUserData`에 표식을 달아 구분한다.
  - **Option 키 일시 해제**(§13 결정 2): 버릴 뻔한 이벤트라도 그 이벤트 자체의 `flags`에 `.maskAlternate`가 있으면 통과시킨다. 키보드 이벤트는 받지 않는다. 마우스 이벤트에 이미 실린 수정 키 상태만 본다. 심사에서 "키 입력을 감시하지 않는다"고 말할 수 있게 하기 위해서다.
  - Option으로 Dock을 옮긴 것은 사용자의 뜻으로 본다. 탭이 통과시킨 이벤트로 Dock이 다른 화면으로 가면, AppModel이 `userOverride`를 켜고 Relocator는 되돌리지 않는다. `userOverride`는 다음 중 하나가 일어나면 꺼진다.
    - Dock이 고정 화면으로 돌아옴. 고정 화면 아래 끝은 막지 않으므로 평소처럼 마우스로 데려오면 된다
    - 메뉴의 "Move Dock back now"
    - 잠자기에서 깨어남, 잠금 해제, 화면 구성 변화
- `GuardSnapshot`은 `OSAllocatedUnfairLock`으로 보호한다(macOS 13+). 콜백은 잠금을 잡고 값 복사만 한다.
- `tapDisabled*`가 오면 즉시 다시 켜고, 횟수를 기록한다. 단, 앱이 스스로 탭을 끌 때도 `tapDisabledByUserInput`이 오므로(F13), 정리가 시작된 탭은 다시 켜지 않는다. 정리할 때 포트 핸들을 잠금 안에서 먼저 비우고, 콜백은 같은 잠금 안에서 핸들이 남아 있을 때만 다시 켠다. 메인 쪽은 2초마다 `CGEvent.tapIsEnabled`를 확인해 꺼져 있으면 다시 켠다. 이 확인은 원본 DockAnchor보다 한 겹 더 있는 안전망이다.
- 버린 이벤트 수만 센다. 좌표 기록은 디버그 빌드에서만 남긴다.

### 5.3 DockLocator

- Dock PID: `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")`. Dock이 다시 시작되면(`NSWorkspace.didLaunchApplicationNotification`) 새로 읽는다.
- Dock 창: 그 PID가 소유하고 레이어가 `CGWindowLevelForKey(.dockWindow)`인 창이다(F7, F8). 창 번호를 캐시해 두고, 평소에는 `CGWindowListCreateDescriptionFromArray([id])`로 창 하나만 조회한다. 창이 없어졌을 때만 전체 목록을 다시 훑는다.
- 전체 목록을 훑을 때 후보(같은 PID, 같은 레이어)가 둘 이상이면 Dock이 옮기는 중이다(F15 DockClone). 후보가 하나가 될 때까지 20ms 간격으로 다시 읽고, 1초가 지나도 하나가 아니면 `.unknown`이다. `onscreen` 값은 조건으로 쓰지 않는다. 자동 숨김이거나 고정 화면에 전체 화면 앱이 있으면 false이기 때문이다(F20, F21).
- 판정: 창 범위와 같은 화면을 찾는다(1pt 허용 오차). 같은 화면이 없으면 가장 많이 겹치는 화면을 고르고, 그것도 없으면 `.unknown`이다. 결과는 `DockPlacement { .display(CGDirectDisplayID), .unknown }`이다.
- 언제 확인하는지: 이벤트가 오면 바로 확인한다(깨어남, 잠금 해제, 화면 구성 변화, Space 변경, Dock 재시작). 그 밖에 3초마다 가볍게 확인한다(창 하나 조회).

### 5.4 Relocator

상태: `idle → waiting(reason) → driving → verifying → idle | failed(attempts)`.

1. **확인**: DockLocator가 고정 화면 밖이라고 할 때만 시작한다(I2).
2. **기다림**: 순수 함수 `RelocationPolicy.decide(_ inputs:) -> .go | .wait(Reason)`가 판단한다. 입력은 다음과 같다(I3).
   - 잠금 여부
   - 콘솔 세션 여부(`kCGSSessionOnConsoleKey`)
   - 마지막 입력 뒤 지난 시간(`CGEventSource.secondsSinceLastEventType(.hidSystemState, …)`, 0.5초 이상 조용해야 함)
   - 버튼 눌림(`CGEventSource.buttonState`. F10 때문에 필수)
   - 일시정지 여부와 Dock 설정
3. **움직이기**:
   - 커서 위치를 저장한다. 숨기지는 않는다. 배경 앱이 커서를 숨기려면 비공개 API가 필요하다.
   - `relocationPoint`보다 40pt 위에서 시작해 3pt씩 내려오고, 맨 아래 줄에 닿으면 그 자리에서 `mouseMoved`를 16ms 간격으로 HID 단계에 보낸다. 줄에 바로 꽂지 않는다. 포인터가 Dock 안에 있다가 warp로 사라진 상태에서는 한 점 방식이 실패한다(F16). 드래그 이벤트는 보내지 않는다(F10).
   - 매 간격마다 DockLocator로 확인한다. 실측 0.33–1.00초에 여유를 둬 최대 2.0초까지 기다린다.
   - 사용자의 실제 입력이 섞이면 즉시 멈춘다. 표식이 없는 이벤트로 구분한다.
4. **복원**: 표식을 단 `mouseMoved` 하나로 커서를 원래 자리로 보낸다. `CGWarpMouseCursorPosition`은 쓰지 않는다. warp는 Dock이 포인터가 아직 자기 위에 있다고 여기게 만들고(F16), 실제 마우스 입력도 잠깐 멈춘다. 취소(잠금, 잠자기, 종료)돼도 복원한다. 사용자가 마우스를 움직여 멈춘 경우에는 복원하지 않고 사용자가 둔 자리에 둔다.
5. **다시 확인**: Dock이 고정 화면에 있으면 끝이다. 아니면 1초, 3초, 10초 뒤에 다시 시도하고, 세 번 실패하면 `failed` 상태가 되어 메뉴에 그대로 표시한다. 다음 트리거가 오면 횟수를 초기화한다.

### 5.5 SessionMonitor

- 잠자기와 깨어남: `NSWorkspace.willSleepNotification`, `didWakeNotification`, `screensDidWakeNotification`
- 빠른 사용자 전환: `sessionDidResignActiveNotification`, `sessionDidBecomeActiveNotification`
- 잠금: 분산 알림 `com.apple.screenIsLocked`, `com.apple.screenIsUnlocked`. 시작할 때는 `CGSSessionScreenIsLocked` 키로 현재 상태를 읽는다(T4 검증 필요).
- Space 변경: `NSWorkspace.activeSpaceDidChangeNotification`
- 모든 신호는 AppModel 한 곳으로 모이고, AppModel이 DockLocator 확인과 Relocator 시작을 결정한다. 원본은 깨어남, 잠금 해제, 화면 연결이 각자 되돌리기를 예약했는데, 그 구조를 피한다.

### 5.6 DockPreferences

샌드박스가 없으므로 Dock 설정을 직접 읽는다(`CFPreferencesAppSynchronize` 다음 `CFPreferencesCopyAppValue`, 도메인 `com.apple.dock`). 관리 프로파일로 강제된 값도 같은 API로 읽힌다.
- **Dock 방향**: `orientation`. 키가 없으면 bottom이다(Kennt Mac에서 확인). `left`나 `right`면 쉬고, 이유를 "Dock is on the left/right"로 표시한다.
- **자동 숨김**: `autohide`. 켜져 있어도 트리거는 맨 아래 1px 줄이므로(F21) 그대로 막는다. 상태 줄에만 쓴다.
- **핫 코너**: `wvous-bl-corner`, `wvous-br-corner`. 값이 0이나 1이 아니면 설정된 것이다(Kennt Mac: `wvous-br-corner = 14` 빠른 메모). 지금은 표시용이고, 모서리 규칙은 T2 결과로 정한다(§5.1).
- **Spaces**: `NSScreen.screensHaveSeparateSpaces`(S5). false면 쉰다. 이때는 시스템이 Dock을 주 화면에 둔다.
- **화면이 하나뿐**이면 쉰다.
- 다시 읽는 때: `NSApplication.didChangeScreenParametersNotification`, Dock 재시작, 3초 확인. Dock 설정을 바꾸면 Dock이 다시 읽으므로, 3초 확인으로 충분하다.
- `visibleFrame` 여백으로 방향을 짐작하던 방식(S6)은 쓰지 않는다. 자동 숨김이면 여백이 0이어서 방향을 알 수 없었다(F21).

### 5.7 PermissionWatch

- `AXIsProcessTrusted()`를 1초마다 확인하고, 분산 알림 `com.apple.accessibility.api`도 받는다(이 알림 이름은 T6에서 검증).
- 권한이 사라졌다고 판단하면 **먼저** `EdgeGuard.stop()`을 동기로 호출한다. 탭을 끄고, 런루프 소스를 제거하고, 포트를 무효화한 다음 상태를 바꾼다(I4). 포럼 보고에 따르면 이 처리로도 먹통을 완전히 막는다는 보장은 없다. 그래서 §12 위험에 남긴다.
- 처음 실행할 때는 설명 화면을 먼저 보여 준다. 그다음 `AXIsProcessTrustedWithOptions(prompt: true)`로 요청하고, S8의 URL로 해당 설정 화면을 연다. macOS 버전마다 그 화면 이름이 다르므로(macOS 27: "Device Control and Data Access"), 안내 문구는 화면 이름 대신 "the privacy setting that lets SpectaDockPin control the pointer"처럼 쓴다.

### 5.8 AppModel

- `@MainActor @Observable final class AppModel`. AppDelegate가 갖고, 실행 직후 `start()`, 종료 직전 `shutdown()`(탭 먼저)을 부른다. 화면은 `.environment(model)`로 받는다. SpectArk처럼 `@State`로 두지 않은 이유는 탭의 시작과 끝을 앱 생명주기에 정확히 묶기 위해서다.
- `status`의 종류:
  - `.pinned(anchorName)`
  - `.relocating`
  - `.paused(PauseReason)`
  - `.needsPermission`
  - `.failed(attempts)`
- 보조 값: 오늘 막은 이벤트 수, 최근 되돌린 시각과 성공 여부.
- 시작 순서는 다음과 같다. `AppRuntime.isUnitTestHost`이면 여기서 멈춘다(I7).
  1. 권한 확인
  2. DisplayMap
  3. DockPreferences
  4. EdgeGuard 시작
  5. 첫 확인

---

## 6. 화면

- `MenuBarExtra`, SF Symbol 템플릿 아이콘(후보 `dock.rectangle`, 실제 이름은 구현 때 확인). 상태별로 모양을 바꾼다. 쉬는 중은 흐리게, 권한 없음과 실패는 느낌표로 표시한다.
- 메뉴 항목:
  - 상태 한 줄. 예: "Dock pinned to LG HDR 4K", "Paused — Dock is on the left"
  - Pin to: Main display(기본) 또는 연결된 화면 목록(§13 결정 3). 선택은 화면 UUID로 저장하고, 그 화면이 연결돼 있지 않으면 주 화면을 쓴다. 메뉴에는 "(not connected)"로 표시한다.
  - Option으로 옮긴 상태일 때는 상태 줄을 "Dock moved with Option — Move back now"로 바꾼다.
  - 메뉴 맨 아래에 "Hold Option to let the Dock move" 안내 한 줄을 둔다.
  - Pause / Resume
  - Move Dock back now. 수동 트리거이며, I3 조건은 그대로 적용한다.
  - Launch at login. `SMAppService.mainApp`을 쓰고 기본값은 꺼짐이다. 사용자가 고를 때만 켠다(SpectArk 규칙).
  - Grant Accessibility…(필요할 때만), Quit
- UI 문자열은 영어 원본으로 쓰고 String Catalog에 넣는다. 번역은 출시를 다시 정할 때 한다(§13 결정 5).

---

## 7. 프로젝트 구조와 규약 (Specta 시리즈 기준)

| 항목 | 규칙 | 근거 |
|---|---|---|
| 빌드 | **XcodeGen `project.yml`**이 기준이다. `.xcodeproj`는 생성물이라 git에서 제외한다 | SpectArk, SpectaKool, SpectaDiary `project.yml`. principles.md |
| 설정 | `SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY complete`(경고를 끄고 넘어가지 않는다), `ENABLE_HARDENED_RUNTIME YES`(공증에 필요), `ENABLE_APP_SANDBOX NO`, `DEVELOPMENT_TEAM 8677QL77VJ`, `MARKETING_VERSION 0.1.0` / `CURRENT_PROJECT_VERSION 1` | SpectArk `project.yml`와 같다 |
| entitlements | `com.apple.security.app-sandbox = false` 하나뿐이다. hardened runtime 예외(JIT, 라이브러리 검증 끄기 등)는 필요 없다 | SpectArk `SpectaBackup.entitlements` |
| 번들 ID | `ai.calidalab.spectadockpin`(2026-06 이후 새 앱은 `ai.calidalab.*`, 소문자) | SpectArk, SpectaBooks, SpectaDiary |
| 배포 대상 | macOS 14.0. `@Observable`, `MenuBarExtra`, `SMAppService`가 모두 된다 | SpectArk |
| 파일 머리 | `@file / @description / @author Kennt Kim / @company Calida Lab / @created / @lastUpdated`, 이어서 `Notes:` 또는 `Key declared values:`(단위와 함정). 수정할 때마다 `@lastUpdated`를 갱신한다. 스크립트와 yml은 `#` 형태, 문서는 HTML 주석 | ~/.claude/CLAUDE.md, SpectaKool CLAUDE.md, SpectaDiary `Paper.swift` |
| 언어 | 코드, 주석, 식별자, UI 원문은 영어. 이 설계서는 한국어 | ~/.claude/CLAUDE.md |
| 상태 | `@MainActor @Observable final class`. `ObservableObject`는 쓰지 않는다. 시스템 접점은 `static let shared`를 최소한으로 쓰고, 테스트할 수 있게 프로토콜 뒤에 둔다 | SpectaKool, SpectaDiary, SpectArk |
| 동시성 | 탭 스레드와 메인 액터 사이는 `OSAllocatedUnfairLock<GuardSnapshot>` 하나로만 오간다. `@unchecked Sendable`이나 `nonisolated(unsafe)`는 이유 주석이 있을 때만 쓴다 | SpectArk `FolderWatcher` 선례 |
| 로그 | `enum AppLog`, subsystem `ai.calidalab.spectadockpin`. 카테고리는 `Guard`, `Dock`, `Relocate`, `Session`, `Permission`(SpectaKool `AppLog` 형식). 좌표와 상태만 남기고, 창 제목이나 앱 이름은 남기지 않는다 | SpectaKool `AppLog.swift`. SpectaLing "사용자 파일 경로 로그 금지" |
| 상수 | 매직 넘버를 흩뿌리지 않는다. `enum PinTuning`에 단위와 함께 모은다. 예: `triggerRowHeight: 1 pt`, `relocationTimeout: 2.0 s`, `driveInterval: 16 ms`, `idleBeforeRelocation: 0.5 s`, `pollInterval: 3 s`. 실측 출처는 §3 번호로 주석에 단다 | "하드코딩 금지"(SpectaKool·SpectaLing CLAUDE.md) |
| 설정 저장 | UserDefaults 키는 `spectadockpin.` 접두사를 붙이고, 한 번 정하면 이름을 바꾸지 않는다 | SpectArk `spectabackup.*`. SpectaKit "저장된 식별자는 그대로" |
| 오류 | 구체적인 오류 타입을 쓰고, 사용자에게 보이는 문장은 따로 둔다. 예: `failed`는 "Dock didn't move back after 3 tries"처럼 구체적으로 쓴다 | SpectArk `InfraError`. "에러는 구체적으로" |
| 다국어 | `Localizable.xcstrings`, 원본 en. 모든 UI 문자열은 카탈로그를 거친다. 번역은 출시를 다시 정할 때 한다(§13 결정 5) | SpectaKool, SpectaKit |
| 브랜드 | Specta 앰버(§13 결정 5). `AccentColor` 애셋은 #F5C400, 다크 모드는 #FFD60A. 코드 토큰은 `Color.spectaYellow`. 앰버는 **채우기에만** 쓰고, 밝은 바탕 위 글자와 기호는 더 진한 앰버(#9A7400)로 쓴다. 메뉴바 아이콘은 흑백 템플릿이다 | SpectaKool `SpectaColors.swift`, SpectaDiary `Paper.swift`(채우기 규칙), SpectArk `AccentColor` |
| 테스트 | Swift Testing(`import Testing`, `@Test(arguments:)`), 타깃 `SpectaDockPinTests`, 파일마다 `Run:` 줄. 테스트 호스트 보호는 `AppRuntime` | SpectaKit, SpectaBooks(최신), SpectArk `AppRuntime` |
| 커밋 | `main`에 직접. Co-Authored-By 없음. 커밋, 푸시, 릴리즈는 Kennt가 말할 때만 | ~/.claude/CLAUDE.md |

폴더(SpectArk 구조를 따른다):

```
SpectaDockPin/
  project.yml
  Docs/DESIGN.md
  SpectaDockPin/
    App/        SpectaDockPinApp, AppDelegate, AppModel, AppSettings, AppLog, AppRuntime,
                LoginItem, PinTuning, Info.plist, SpectaDockPin.entitlements
    Features/   MenuBar/MenuBarView, MenuBar/StatusPresentation, Onboarding/PermissionView (+ OnboardingWindow)
    Services/   Displays/  DisplayMap (pure), DisplayWatcher
                Guard/     EdgeGuard (tap thread), EdgeRule (pure), GuardSnapshot
                Dock/      DockLocator, DockPreferences
                Relocation/Relocator, RelocationPolicy (pure)
                System/    SessionMonitor, PermissionWatch
    Resources/  Assets.xcassets (AppIcon, AccentColor), Localizable.xcstrings, InfoPlist.xcstrings
  SpectaDockPinTests/   DisplayMapTests, EdgeRuleTests, RelocationPolicyTests, DockPlacementTests
  tools/DockProbe/       the §3 experiment CLI, kept for regression checks
  tools/AppIcon/make_icon.swift  앱 아이콘 원본(CoreGraphics). `xcrun swift tools/AppIcon/make_icon.swift`로 AppIcon.appiconset을 다시 만든다
  scripts/release.sh     Developer ID 서명, 공증, DMG
```

---

## 8. 테스트

단위 테스트는 순수 부분만 다룬다. 탭, 커서, Dock은 테스트 호스트에서 절대 건드리지 않는다(I7).
- `DisplayMapTests`
  - 좌우 배치(Kennt 실제 구성), 위아래 배치, 계단식 배치, 화면 하나
  - 고정 화면 UUID가 사라졌을 때 주 화면으로 돌아가는지
  - 아래에 맞닿은 구간을 빼는지
  - `relocationPoint`가 모서리를 피하는지
- `EdgeRuleTests`: 줄 경계값 `maxY−1`, `maxY−1−ε`, 모서리 픽셀, 앱이 보낸 표식 이벤트, Option 플래그가 있는 이벤트
- `RelocationPolicyTests`: 잠금, 콘솔 아님, 버튼 눌림, 입력 직후, 일시정지일 때 각각 `.wait`가 나오는지
- `DockPlacementTests`: 창 범위가 화면과 같을 때, 겹칠 때, 없을 때의 판정

`tools/DockProbe`(§3 실험을 정리한 SwiftPM CLI, `xcrun swift build`로 빌드). 앱 코드와 일부러 분리했다. 앱의 DisplayMap이나 DockLocator에 버그가 있어도 macOS 동작 변화를 가리지 않게 하기 위해서다.
- 읽기만 함: `info`(화면, Dock 창, 막을 줄, 되돌릴 점, 권한, 세션), `where`(Dock 위치)
- 실제 입력 기록: `watch`(듣기만 하는 탭, 아무것도 바꾸지 않음), `guard`(막을 줄의 이벤트를 버림, `--corner block|pass`, Option 해제 포함). 둘 다 화면 아래 줄 방문마다 한 줄(줄별 이벤트 수, 종류, deltaY, y 값)과 Dock 이동 때 직전 포인터 상황을 남긴다. `--raw`는 이벤트 하나하나를 찍는다
- 커서를 움직임: `trigger <x> <y>`(합성 이벤트로 머무르기 실험, `--guard`면 F4 재현), `home`(Dock을 고정 화면으로 되돌림)

macOS가 바뀌면 다시 돌려 §3 표가 아직 맞는지 확인한다. `trigger`와 `home`은 Kennt의 커서와 Dock을 실제로 움직이므로, 실행 전에 알린다.

**실제 마우스로 확인할 것 (Kennt 참여)** — 듣기만 하는 기록 도구를 띄우고 진행:
- **T1** 실제 파일을 끌어 Dell과 맥북 아래 끝에 머물기. 막는 장치가 없을 때 넘어가는지, 있을 때 막히는지 확인한다(F10 보완, 원본 #30).
- **T2** 막는 장치를 켠 채 각 화면 오른쪽 아래 핫 코너(빠른 메모)가 작동하는지 확인한다. 모서리도 Dock을 옮기므로(F23), 통과시키면 그 모서리에서 Dock이 넘어갈 수 있다. 막혔을 때 어떻게 할지는 이 결과를 보고 정한다.
- **T3** 실제 마우스로 아래로 밀 때와 그냥 지나갈 때를 비교해 F1, F3이 실제 입력에서도 같은지 확인한다.
- **T4** 화면을 잠갔을 때 `CGSSessionScreenIsLocked`가 생기는지, 잠금 알림 두 개가 오는지 확인한다.
- **T5** Dock 자동 숨김을 켰을 때도 트리거가 맨 아래 1px 줄인지 확인한다. 합성 이벤트로는 통과했다(F21). 실제 마우스로 한 번 더 본다.
- **T6** 손쉬운 사용 권한을 껐을 때 오는 알림 이름을 확인한다. **탭이 켜진 상태에서는 하지 않는다.** 듣기만 하는 도구로 알림만 확인한다(§12 먹통 위험).
- **T7** 잠자기에서 깨어날 때와 모니터를 뽑았다 꽂을 때, Dock이 실제로 어디로 가는지와 앱이 잘 되돌리는지 확인한다.
- **T9** 보조 화면에 전체 화면 앱(F20 합성 확인)과 Teams·Zoom 화면 공유가 있을 때 실제 마우스로 막히는지 확인한다. Sidecar 화면도 연결할 수 있으면 함께 본다(DockLock 이슈 #3, #4, #6).

---

## 9. 배포와 서명

- **출시 예정 없음**(§13 결정 2). 샌드박스 없이 Kennt가 직접 쓴다.
- 로컬 빌드도 **Apple Development 인증서로 서명한다**(Automatic, 팀 8677QL77VJ). 임시 서명은 빌드할 때마다 서명 정보가 바뀌어 권한이 풀린다. 같은 인증서로 다시 빌드하면 권한이 유지된다(S7). 시험할 때는 `/Applications`에 설치한다(S7).
- 설치용 빌드는 `scripts/release.sh`로 만든다. Release로 아카이브하고, Developer ID로 내보내 서명을 확인한 뒤, 공증하고 스테이플한다. 그다음 DMG를 만들어 다시 서명, 공증, 스테이플한다. SpectArk 파이프라인에서 Sparkle 부분만 뺀 것이다. 공증 프로필은 `WhisPlayInfo-notary`를 쓴다.
- Developer ID 서명과 Apple Development 서명은 서로 다른 서명으로 보이므로, 설치용 빌드로 바꿀 때 손쉬운 사용 권한을 한 번 다시 줘야 한다. 권한을 바꾸기 전에는 앱을 종료한다(§12).
- 업데이트 장치(Sparkle)와 네트워크는 없다(I8). 새 빌드는 직접 설치한다.

---

## 10. 단계

| 단계 | 내용 | 완료 기준 |
|---|---|---|
| P0 | `tools/DockProbe` 정리 + 실제 마우스 확인 T1–T3 | §3 표의 남은 칸이 채워지고, 모서리 처리가 결정됨. **완료(2026-10-18, R1–R5)** |
| P1 | 골격: `project.yml`, App 폴더(AppLog, AppRuntime, AppSettings), PermissionWatch, 온보딩 | 서명된 빌드가 뜨고, 권한을 주거나 빼는 상태가 메뉴에 보임 |
| P2 | DisplayMap + EdgeRule + EdgeGuard + 단위 테스트 | Dell과 맥북 아래 끝에서 Dock이 넘어가지 않음(T3 재실행) |
| P3 | DockLocator + DockPreferences + 쉬는 조건 | 메뉴 상태가 실제 Dock 위치와 항상 같음 |
| P4 | Relocator + RelocationPolicy + SessionMonitor | T4, T7 통과. 잠긴 상태에서는 커서가 절대 움직이지 않음 |
| P5 | 메뉴 UI 완성, 고정 화면 선택, 로그인 항목, String Catalog | 모든 UI 문자열이 카탈로그에 있음 |
| P6 | 아이콘(`tools/AppIcon`, 2026-10-18 완료: 파란 모니터의 Dock 막대를 앰버 핀이 고정하는 모양, Specta 유리 바탕), `scripts/release.sh`(Developer ID 서명, 공증, DMG) | 공증된 DMG를 설치해 손쉬운 사용 권한을 주고 쓸 수 있음 |

---

## 11. 검토한 대안

| 대안 | 판단 |
|---|---|
| 아래 10px 띠를 통째로 막고 모서리에서 커서를 15px 올리기(원본 DockAnchor) | 기각. F2에 따르면 1px이면 충분하다. 띠가 넓으면 그 띠 안의 호버와 클릭이 죽고, 커서를 강제로 옮기는 동작이 생긴다 |
| 커서를 맨 아래 줄에 못 닿게 막기(`CGAssociateMouseAndMouseCursorPosition` + warp, EdgeCase 방식) | 기각. 커서 자체를 조작해서 개입이 더 크다. F4에 따르면 이벤트만 막아도 되기 때문에 필요 없다 |
| 이벤트를 Dock에만 보내 커서 없이 되돌리기 | 기각. F6에서 작동하지 않았다 |
| "디스플레이마다 별도의 Spaces" 끄기 | 앱 없이 해결된다. 하지만 메뉴 막대가 주 화면에만 생기고, 전체 화면 앱을 띄우면 다른 화면이 비어서 Kennt의 세 화면 환경에는 맞지 않는다. 앱은 이 설정을 감지하면 쉰다(§5.6) |
| `killall Dock` 또는 `orientation`을 바꿔 위치 재설정 | 검증되지 않았다. 화면이 깜빡이고 전체 화면 앱에 영향을 준다는 보고가 있다. 기각 |
| 상용 DockLock | 구현이 공개되지 않았고 유료다. 판단 근거로만 쓴다 |
| 샌드박스 앱으로 Mac App Store 출시(v1 중간안) | 접음(2026-10-18, Kennt). 출시 예정이 없으므로 샌드박스 제약(Dock 설정을 못 읽음, S4)을 질 이유가 없다. 다시 출시를 정하면, 샌드박스에서 막는 것과 되돌리는 것이 된다는 실측(S1–S3)이 남아 있다 |
| 권한 없이 막기: 전역 마우스 모니터 + 커서를 위로 밀어 올리기(DockLock 추정 방식, F17, F18) | 기각(2026-10-18, Kennt 결정 7). 커서를 조작해서 I1을 어긴다. 세게 밀면 뚫리고(F17 L=20, s=25), 막으려면 커서가 크게 튄다 |
| 보조 화면 맨 아래를 덮는 투명 창 | 기각. F19에서 막지 못했다 |

---

## 12. 위험과 알려진 한계

- **권한을 끄면 입력이 먹통이 될 수 있다(포럼 844416).** I4로 줄이지만, WindowServer 쪽 문제라면 앱이 막을 수 없다. 사용 안내에 "권한을 끄기 전에 앱을 종료하라"를 적는다. 메뉴의 Quit은 탭을 먼저 제거하고 종료한다.
- **문서화되지 않은 동작에 기댄다.** Dock의 트리거 규칙(F1–F5, F17, F23), Dock 창 범위가 화면과 같다는 점(F8), 창 목록 필드(F7)가 모두 그렇다. macOS가 바뀌면 `DockProbe`로 다시 확인한다. 확인이 실패하면 앱은 `.unknown`으로 쉬고, 엉뚱한 동작은 하지 않는다.
- 보조 화면 맨 아래 1px 줄에서는 그 아래 앱이 호버를 받지 못한다. 클릭은 막지 않는다. 영향은 사실상 없다.
- 합성 이벤트와 실제 마우스는 다를 수 있다(F10, F11). T1–T3 전까지 §3은 합성 이벤트 기준이다.
- 위아래 배치와 자동 숨김은 Kennt 환경에 없어서 실측하지 않았다. 단위 테스트와 T5로 대신한다.
- Relocator는 실제 커서를 움직인다. 사람이 있을 때만(I3), 위에서 다가가는 방식으로(F16) 움직인다.

---

## 13. 결정 (2026-10-18, Kennt)

1. **이름과 번들 ID**: 앱 이름은 **SpectaDockPin**(SiliconDockPin에서 변경). 번들 ID는 `ai.calidalab.spectadockpin`이다. 2026-06 이후 새 앱의 형식(소문자)을 따른다. 
2. **배포**: ~~앱 스토어 출시~~ → **출시 예정 없음.** 샌드박스 없음, Developer ID 서명 + 공증(§9). "그까잇거 여차하면 출시 안 하면 되지", "샌드박스 의식하지 말고"(같은 날 변경). Sparkle 없음.
3. **Option 키 일시 해제**: 넣는다. 마우스 이벤트의 수정 키 플래그만 보고, Option으로 옮긴 위치는 존중한다(§5.2).
4. **고정 화면 선택**: 메뉴에서 고를 수 있게 하고, 기본값은 주 화면이다(§6).
5. **번역 언어**: 출시할 때의 계획은 Specta 기본 5개 언어(ko, ja, zh-Hans, zh-Hant, id) + 원본 en이었다. 출시 예정이 없어서 지금은 en만 쓰고, 문자열은 모두 String Catalog에 둔다(§7).
6. **강조색**: Specta 앰버(§7 브랜드).
7. **막는 방식**: 손쉬운 사용 권한으로 이벤트를 버리는 지금 설계 그대로 간다. 권한 없이 커서를 밀어 올리는 방식은 하지 않는다(§11).
8. **모서리**: 막는다(F23). 막아도 핫 코너는 작동했다(R3). 예외는 두지 않는다.

폴더 이름: `~/Desktop/Developments/SiliconDockPin` → `SpectaDockPin`으로 바꿨다(2026-10-18). 폴더 이름과 제품 이름이 다른 Specta 앱이 이미 셋이나 있어서, 이번에는 처음부터 맞췄다.
