# Supercent 로그 수집 파이프라인

수천만 글로벌 유저의 게임에서 발생하는 **초당 수만 건의 인게임 로그**를 유실 없이 받아내고 적재하기 위한 로그 수집 파이프라인입니다. 로그 수집 API 서버를 직접 구현·컨테이너화하고, 그 뒤의 적재 인프라를 **큐(SQS) + DB(MongoDB)** 구조로 설계했습니다.

> 명령어 한 줄(`docker compose up --build`)로 전체 테스트 환경이 그대로 복제됩니다.

---

## 아키텍처 (로컬 / docker-compose)

```
                                  ┌───────────────────────────────────────────┐
                                  │        docker-compose 가상 네트워크          │
                                  │                                             │
  게임 클라이언트                 │   ┌─────────┐   send    ┌───────────────┐   │
  POST /api/v1/logs  ───► :3000 ──┼──►│  API    │──────────►│  SQS (main)   │   │
  (JSON 로그)                     │   │ Express │           │ supercent-    │   │
                                  │   └─────────┘           │  queue        │   │
                                  │                         └───────┬───────┘   │
                                  │                          poll   │           │
                                  │                     ┌───────────▼───────┐   │
                                  │        store        │      Worker       │   │
                                  │   ┌─────────────┐◄──┤  (SQS consumer)   │   │
                                  │   │  MongoDB    │   └───────────┬───────┘   │
                                  │   │ (volume)    │        5회 실패│           │
                                  │   └─────────────┘     ┌─────────▼───────┐   │
                                  │                       │  SQS (DLQ)      │   │
                                  │                       │ supercent-      │   │
                                  │                       │  queue-dlq      │   │
                                  │                       └─────────────────┘   │
                                  └───────────────────────────────────────────┘
```

| 컴포넌트 | 역할 | 이미지 |
|---|---|---|
| **api** | `POST /api/v1/logs` 수신 → 검증 → SQS 전송 (호스트 `:3000` 개방) | Node.js / Express |
| **worker** | SQS 폴링 → MongoDB 적재, 실패 시 DLQ로 격리 | Node.js |
| **localstack** | 로컬에서 AWS SQS를 모사 | localstack |
| **queue-init** | 기동 시 메인 큐 + DLQ + redrive policy 생성 (1회성) | amazon/aws-cli |
| **mongodb** | 로그 최종 적재소 (볼륨으로 영속화) | mongo |

---

## 선택 이유 (Rationale)

로그 적재 방식으로 **큐(Queue, B안) + DB(C안) 조합**을 선택했습니다. 인프라 엔지니어 관점의 이유는 다음과 같습니다.

### 1. 왜 큐(SQS)를 앞단에 두는가 — *트래픽 흡수 + 디커플링*
- **스파이크 흡수(버퍼링)**: "초당 수만 건"의 트래픽은 항상 균일하지 않습니다. API는 로그를 받아 **큐에 넣기만 하고 즉시 200을 반환**하므로, 적재 처리 지연이 API 응답 지연으로 전이되지 않습니다. 트래픽이 폭증해도 API가 죽지 않고 큐가 완충 역할을 합니다.
- **수집과 처리의 분리**: 수집(API)과 적재(Worker)를 분리하면 각각 독립적으로 배포·확장할 수 있습니다.
- **수평 확장**: 소비자(Worker)를 `docker compose up --scale worker=N`으로 늘리면 처리량이 선형으로 증가합니다.

### 2. 왜 DB(MongoDB)를 최종 적재소로 두는가 — *비정형 로그에 적합*
- 인게임 로그는 이벤트(유저 행동, 재화 소비, 시스템 에러)마다 필드가 제각각인 **비정형 JSON**입니다. 스키마를 강제하지 않는 **document store**가 구조 변경 없이 그대로 적재하기에 적합합니다.
- 컨테이너 하나로 즉시 기동되고, `find()` 한 번으로 적재 결과를 바로 확인할 수 있어 **검증에도 유리**합니다.

### 3. 왜 파일(A안)이 아닌가
- 단일 파일 적재는 동시성 제어, 다중 인스턴스 간 파일 공유, 대용량 조회에서 한계가 있습니다. "대량의 글로벌 트래픽 + 분산 처리" 가정에는 큐 + DB 조합이 근본적으로 유리합니다.

### 4. 유실 없이 적재(No Data Loss) — 이 설계의 핵심
로그 파이프라인에서 가장 중요한 **유실 방지**를 다음 3중 장치로 보장합니다.

1. **API는 SQS 전송이 성공해야 200을 반환** — 큐에 안전히 들어간 뒤에만 성공 응답하므로, 실패 시 클라이언트가 재전송할 수 있습니다.
2. **Worker는 적재(insert) 성공 후에만 메시지 삭제** — at-least-once 처리. 워커가 처리 도중 죽어도 메시지는 삭제되지 않아 visibility timeout 후 **자동 재처리**됩니다.
3. **DLQ(Dead Letter Queue) + native redrive** — 계속 실패하는 poison 메시지는 5회 재시도 후 SQS가 자동으로 DLQ로 격리합니다. 덕분에 문제 메시지 하나가 큐 전체를 막거나 무한 재시도되는 일이 없고, **실패한 메시지도 버려지지 않고** 보관됩니다.

### 5. 로컬(MongoDB) vs AWS(S3) — 환경별 목적에 맞춘 선택
- **로컬**은 빠른 개발·검증에 적합한 **MongoDB(document DB)** 로 적재합니다.
- **AWS 설계**(선택 과제)에서는 대규모 수집·보관·분석에 최적화된 대표 로그 스토리지 **S3**를 적재소로 사용합니다. (아래 [AWS 인프라 설계](#선택-과제-aws-인프라-설계--terraform) 참조)

---

## 실행 가이드

### 사전 요구 사항
- Docker / Docker Compose (v2)

### 1) 전체 환경 기동
프로젝트 루트에서 아래 한 줄이면 됩니다.

```bash
docker compose up --build
```

- 최초 실행 시 `api` / `worker` 이미지가 빌드되고, `localstack` → `queue-init`(큐+DLQ 생성) → `mongodb` → `api` / `worker` 순서로 의존성에 맞춰 기동됩니다.
- 백그라운드로 띄우려면: `docker compose up --build -d`
- 기동 상태 확인: `docker compose ps` (localstack/mongodb/api가 `healthy`가 되면 준비 완료)

### 2) 종료
```bash
docker compose down          # 컨테이너 정리 (볼륨 유지)
docker compose down -v       # 볼륨까지 완전 삭제
```

### 3) 포트 구성
| 서비스 | 호스트 포트 | 용도 |
|---|---|---|
| api | `3000` | **로그 수신 엔드포인트** (외부 개방) |
| localstack | `4566` | (디버깅용) SQS 모사 |
| mongodb | `27017` | (디버깅용) 적재 결과 조회 |

---

## 검증 결과

아래는 실제로 기동 후 로그를 전송하고 인프라에 도달했음을 확인한 과정입니다.

### ✅ 1. 정상 로그 적재 (API → SQS → Worker → MongoDB)

**① 로그 전송 (curl):**
```bash
curl -X POST http://localhost:3000/api/v1/logs \
  -H "Content-Type: application/json" \
  -d '{"event":"login","userId":123,"coins":500}'
```

**응답 (200 OK):**
```json
{"message":"Log data sent to SQS successfully.","messageId":"44823cb7-c202-4bbd-8863-84c7ebc26811"}
```

**② Worker 처리 로그:**
```bash
docker compose logs worker | tail
```
```
Connected to MongoDB: supercent.logs
Message processed: 44823cb7-c202-4bbd-8863-84c7ebc26811
```

**③ MongoDB 적재 확인:**
```bash
docker exec supercent-mongodb mongosh --quiet supercent \
  --eval 'db.logs.find().sort({storedAt:-1}).limit(1)'
```
```js
[
  {
    _id: ObjectId('...'),
    messageId: '44823cb7-c202-4bbd-8863-84c7ebc26811',
    receivedAt: '2026-07-12T08:15:30.812Z',
    payload: { event: 'login', userId: 123, coins: 500 },
    storedAt: ISODate('2026-07-12T08:15:30.905Z')
  }
]
```
→ 전송한 로그가 큐를 거쳐 DB까지 **유실 없이 도달**함을 확인.

### ✅ 2. 유실 방지(DLQ) 검증

처리에 계속 실패하는 메시지가 버려지지 않고 DLQ로 격리되는지 확인합니다.

**① 깨진(poison) 메시지를 큐에 직접 투입:**
```bash
docker exec supercent-localstack awslocal sqs send-message \
  --queue-url http://localhost:4566/000000000000/supercent-queue \
  --message-body 'this-is-not-json{'
```

**② 5회 재시도 후 DLQ 적재 확인** (VisibilityTimeout 30s 기준 약 2~3분 소요):
```bash
# DLQ에 쌓인 메시지 개수 확인
docker exec supercent-localstack awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/supercent-queue-dlq \
  --attribute-names ApproximateNumberOfMessages

# DLQ 메시지 내용 + 수신 횟수(ApproximateReceiveCount) 확인
docker exec supercent-localstack awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/supercent-queue-dlq \
  --attribute-names ApproximateReceiveCount --visibility-timeout 0
```

**결과:**
```
- Worker 로그: "Failed to process message: SyntaxError ..." 5회 반복 (삭제하지 않음)
- 메인 큐 ApproximateNumberOfMessages: 0   (메시지가 빠져나감)
- DLQ ApproximateNumberOfMessages: 1        (격리 성공)
- DLQ 메시지 ApproximateReceiveCount: 6      (maxReceiveCount=5 초과 → 자동 이동)
```
→ 실패한 메시지도 **유실되지 않고** DLQ에 안전하게 보관됨을 확인.

### (참고) 큐 상태 조회
```bash
docker exec supercent-localstack awslocal sqs list-queues
docker exec supercent-localstack awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/supercent-queue \
  --attribute-names RedrivePolicy
```

---

## 프로젝트 구조
```
.
├── api/                    # 로그 수집 API 서버 (Express)
│   ├── routes/logs.js      #   POST /api/v1/logs 핸들러 (검증 + SQS 전송)
│   ├── services/sqs.js     #   SQS SendMessage
│   ├── server.js           #   /healthz, JSON 파싱, 에러 핸들러
│   └── Dockerfile
├── worker/                 # SQS 소비 → MongoDB 적재 워커
│   ├── services/sqs.js     #   ReceiveMessage / DeleteMessage
│   ├── db/mongo.js         #   MongoDB insert
│   ├── worker.js           #   폴링 루프 (실패 시 미삭제 → 재처리/DLQ)
│   └── Dockerfile
├── scripts/init-sqs.sh     # 큐 + DLQ + redrive policy 초기화
├── docker-compose.yml      # 전체 인프라 정의
├── terraform/              # (선택 과제) AWS IaC
└── README.md
```

---

## 환경 변수

`docker-compose.yml`에 로컬 테스트용 값이 명시되어 있습니다. (localstack 더미 크레덴셜·서비스 호스트명 등 **비민감 값**이라 재현성을 위해 하드코딩했으며, 실제 운영이라면 시크릿은 `.env` / AWS Secrets Manager 등으로 분리합니다.)

| 변수 | 설명 |
|---|---|
| `PORT` | API 포트 (기본 3000) |
| `SQS_ENDPOINT` | SQS 엔드포인트 (로컬은 localstack) |
| `SQS_QUEUE_URL` | 로그 큐 URL |
| `MONGO_URI` / `MONGO_DB` / `MONGO_COLLECTION` | MongoDB 접속 정보 |

---

## 선택 과제: AWS 인프라 설계 + Terraform

> 실제 프로비저닝 없이 **설계안 + IaC 코드**만 제출합니다. (`terraform/` 참조)

### 아키텍처 개요
```
Route53 → ALB (Public Subnet, Multi-AZ)
            │
            ▼
        ECS API (Fargate, Private Subnet)  ── send ──►  SQS ──► ECS Worker ──► S3 (raw logs)
                                                          │                        │
                                                          ▼                        ▼
                                                         DLQ                 Glue Catalog → Athena
 CI/CD: GitHub → ECR → ECS 배포
```

![AWS Architecture](./documents/aws-architecture.png)

### 포함 요소
- **네트워크**: VPC(`10.20.0.0/16`), **2개 AZ**에 걸친 Public/Private Subnet, IGW, **AZ별 NAT Gateway**(고가용성), 라우팅 테이블
- **부하 분산**: 퍼블릭 **ALB** → Private Subnet의 ECS API 태스크로 분산 (`/healthz` 헬스체크)
- **컨테이너 서비스**: **ECS Fargate** — API 서비스(오토스케일 2~10) + Worker 서비스(오토스케일 2~20), **ECR** 이미지 저장소
- **로그 적재(관리형)**: **SQS**(+ DLQ redrive, `maxReceiveCount=5`) → **S3**(raw logs) → **Glue Data Catalog** → **Athena**(SQL 조회)
- **보안/권한**: 최소 권한 IAM Task Role(API: SQS 전송 / Worker: SQS 수신·삭제 + S3 적재), S3 퍼블릭 액세스 차단, ALB→ECS 보안그룹 제한
- **관측성**: CloudWatch Logs (API/Worker, 14일 보존)

### 로컬 ↔ AWS 일관성
- 로컬의 **SQS + DLQ redrive** 구조가 AWS([`terraform/log_storage.tf`](terraform/log_storage.tf))와 **동일한 방식**으로 설계되어, 로컬에서 검증한 유실 방지 로직이 운영 설계에도 그대로 반영됩니다.
- 적재소는 환경 목적에 맞게 분리: **로컬=MongoDB**(빠른 개발·검증), **AWS=S3**(대규모 보관·Athena 분석).

### Terraform 구성
| 파일 | 내용 |
|---|---|
| `network.tf` | VPC, Subnet, IGW, NAT, 라우팅 |
| `ecs.tf` | ALB, ECS 클러스터/서비스/태스크 정의 |
| `ecs_autoscaling.tf` | API/Worker 오토스케일링 |
| `security.tf` | 보안 그룹 |
| `iam.tf` | Task 실행/권한 Role |
| `log_storage.tf` | SQS, DLQ, S3, Glue, Athena |
| `ecr.tf` | 컨테이너 이미지 저장소 |
