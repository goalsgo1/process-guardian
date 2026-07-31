# ProcessGuardian

macOS 메뉴바에서 디스크 사용률을 실시간으로 보여주고, 바로 정리까지 할 수 있는 작은 유틸리티입니다.

디스크 여유 공간이 부족해서 스왑이 제대로 안 잡히고, 그 상태에서 메모리 압박이 겹쳐 커널 패닉(강제 재부팅)까지 겪었던 경험에서 시작된 프로젝트입니다.

## 기능

- 메뉴바에 디스크 사용률(%)과 여유 공간을 상시 표시, 60초마다 자동 갱신
- 사용률에 따라 색상 표시: 80% 미만 초록 / 80~89% 노랑 / 90% 이상 빨강
- 클릭하면 용량을 많이 차지하는 항목을 자동 스캔해서 리스트로 보여줌
  - npm 캐시, npx 캐시, CoreSimulator 캐시, 안 쓰는 iOS 시뮬레이터 런타임, Downloads 중복 설치파일, node_modules, 앱 캐시(VSCode/Chrome/Telegram/pip 등)
- 항목별 위험도를 3단계로 분류해서 표시
  - 🟢 완전 자동(재생성 가능) 🟡 확인 후 자동(동적 검증 통과 시) 🔴 사용자 확인 필수(기본 미체크)
- 삭제 전 확인 다이얼로그, 실행 중 프로세스/설치 여부 등 실행 직전 재검사
- 정리 실행 이력을 파일로 기록하고, 앱 안에서 세션별로 모아보고 이미지로 캡쳐 가능
- Docker는 자동 스캔에서 제외하고 별도 버튼으로만 검사 — 이미지·볼륨은 보존하고 미사용 리소스만 정리

## 요구 사항

- macOS 13 (Ventura) 이상

## 설치

[Releases](../../releases)에서 최신 `ProcessGuardian-*.zip`을 받아 압축을 풀고 `/Applications`로 옮긴 뒤 더블클릭하면 됩니다. Developer ID로 서명·공증된 앱이라 별도 보안 경고 없이 실행됩니다.

## 사용법

- 왼쪽 클릭: 정리 팝업 열기/닫기
- 오른쪽 클릭: 종료 메뉴

## 소스에서 빌드하기

```bash
git clone <this-repo>
cd process-guardian
./build-app.sh
```

`dist/ProcessGuardian.app`이 생성됩니다. 직접 배포하려면 본인 소유의 Developer ID Application 인증서로 `sign-and-notarize.sh`의 `SIGNING_IDENTITY`를 바꿔서 서명·공증하세요.

## 라이선스

MIT License — [LICENSE](LICENSE) 참고
