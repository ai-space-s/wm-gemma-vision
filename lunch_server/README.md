# Meal Server

Flask 기반 식단 서버입니다. `cloudflared`가 로컬 `127.0.0.1:7860`으로 터널링하면 `demo.krestine.cc`에서 접근할 수 있습니다.

## 실행

```powershell
cd lunch_server
python -m pip install -r requirements.txt
python app.py
```

기본 포트는 `7860`입니다. 다른 포트가 필요하면 `PORT` 환경 변수를 설정합니다.

## 주요 경로

- `/` 일반 식단 달력
- `/admin` 관리자 달력, 수동 편집, XLSX 가져오기
- `/admin/users` 사용자 등록, 삭제, 비밀번호 변경
- `/api/meals?date=YYYY-MM-DD&meal=all` 앱 연동용 JSON API
- `/api/meals?date=YYYY-MM-DD&meal=breakfast`
- `/api/meals?date=YYYY-MM-DD&meal=lunch`
- `/api/meals?date=YYYY-MM-DD&meal=dinner`
- `/api/menus?year=2026&month=4` 달력 월별 데이터

외부 Android 기기는 로컬 주소가 아니라 다음 공개 주소를 호출합니다.

```text
https://demo.krestine.cc/api/meals?date=2026-04-21&meal=all
```

브라우저에서 `https://demo.krestine.cc`로 접속하면 일반 페이지가 열리고, 관리자 페이지는 `https://demo.krestine.cc/admin`입니다. 오늘, 내일, 다음 주 월요일 같은 상대 날짜 해석은 Android 앱의 function call 단계에서 `YYYY-MM-DD`로 확정한 뒤 이 API를 호출해야 합니다.

사용자는 모두 관리자 권한을 가집니다. 관리자 계정은 환경 변수 `LUNCH_ADMIN_USERNAME`과 `LUNCH_ADMIN_PASSWORD` 또는 `LUNCH_ADMIN_PASSWORD_HASH`로 초기 등록할 수 있습니다. 환경 변수가 없고 사용자가 하나도 없으면 첫 실행 때 `data/admin_initial_password.txt`에 임시 비밀번호가 생성됩니다. 사용자 ID는 서버 로컬 pepper로 HMAC-SHA256 해시 처리되어 `data/users.json`에 저장되고, 비밀번호는 Werkzeug password hash로 저장됩니다.

로그인 보안 설정은 필요하면 다음 환경 변수로 조정합니다.

- `LUNCH_LOGIN_ATTEMPTS_LIMIT`: 기본 `5`
- `LUNCH_LOGIN_LOCKOUT_SECONDS`: 기본 `900`
- `LUNCH_COOKIE_SECURE`: HTTPS 운영 환경에서는 `1`

## 응답 상태

- `ok`: 식단 있음
- `no_menu_info`: 해당 날짜 식단 정보 미등록
- `no_meal`: 주말, 휴무, 행사 등으로 식사 없음
- `error`: 날짜 형식, 서버 처리 오류 등

식단 데이터는 `data/menus.json`에 저장되고, 사용자 데이터는 `data/users.json`에 저장됩니다.
