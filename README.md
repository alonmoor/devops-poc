# devops-poc

POC ל-CI/CD + GitOps + IaC + Secrets Management עבור שני microservices
(`catalog-api` — פנימי בלבד, `orders-api` — נחשף החוצה) הרצים על
Kubernetes.

## מבנה הריפו

```
services/catalog-api/    קוד + Dockerfile + tests (FastAPI)
services/orders-api/     קוד + Dockerfile + tests (FastAPI, קורא ל-catalog-api)
helm/catalog-api/        Helm chart + values לכל סביבה (dev/staging/prod)
helm/orders-api/         Helm chart + values לכל סביבה, כולל Ingress
terraform/               מודול namespace (RBAC/NetworkPolicy/ResourceQuota/Vault auth)
                          + root module לכל סביבה
argocd/                  ApplicationSets (auto-sync dev/staging, manual-only prod)
platform/                משאבי bootstrap ברמת פלטפורמה (SecretStore)
Jenkinsfile               Build → Test → SAST → Trivy → Push → GitOps bump
docs/                     DECISIONS.md + SECRETS.md
```

## הרצה מקומית מול kind

### דרישות מוקדמות
- Docker
- [kind](https://kind.sigs.k8s.io/)
- kubectl, helm
- (אופציונלי, להדגמת Ingress) `kind` עם [תוסף ingress-nginx](https://kind.sigs.k8s.io/docs/user/ingress/)

### שלבים

```bash
# 1. יצירת קלאסטר מקומי
kind create cluster --name devops-poc

# 2. בניית ה-images מקומית (ללא push לרג'יסטרי חיצוני)
docker build -t catalog-api:local services/catalog-api
docker build -t orders-api:local services/orders-api

# 3. טעינת ה-images ישירות ל-kind (עוקף Registry לצורך הדגמה מקומית)
kind load docker-image catalog-api:local --name devops-poc
kind load docker-image orders-api:local --name devops-poc

# 4. יצירת namespace (בדר"כ נעשה ע"י Terraform - כאן ידני לצורך POC מהיר)
kubectl create namespace catalog-dev
kubectl create namespace orders-dev

# 5. פריסה עם Helm ישירות (עוקף ArgoCD לצורך הדגמה מקומית מהירה;
#    בסביבה אמיתית ArgoCD הוא זה שמריץ helm template/install)
helm install catalog-api helm/catalog-api \
  -f helm/catalog-api/values.yaml -f helm/catalog-api/values-dev.yaml \
  --set image.repository=catalog-api --set image.tag=local \
  --set secrets.enabled=false \
  -n catalog-dev

helm install orders-api helm/orders-api \
  -f helm/orders-api/values.yaml -f helm/orders-api/values-dev.yaml \
  --set image.repository=orders-api --set image.tag=local \
  --set secrets.enabled=false --set ingress.enabled=false \
  -n orders-dev

# 6. בדיקת התקינות
kubectl -n catalog-dev port-forward svc/catalog-api 8080:8080 &
curl localhost:8080/catalog

kubectl -n orders-dev port-forward svc/orders-api 8081:8080 &
curl -X POST localhost:8081/orders -H 'Content-Type: application/json' \
  -d '{"sku": "sku-1001", "quantity": 2}'
```

`secrets.enabled=false` ו-`ingress.enabled=false` ב-flags למעלה עוקפים
את ברירת המחדל ב-`values-dev.yaml`, כי הרצה מקומית מהירה לרוב לא כוללת
Vault/ESO ו-ingress-nginx מותקנים מראש. להדגמה מלאה של זרימת ה-secrets
ר' `docs/SECRETS.md`.

## הרצת הבדיקות בלבד (ללא קלאסטר בכלל)

```bash
cd services/catalog-api && pip install -r requirements.txt pytest httpx && pytest tests/ -v
cd services/orders-api  && pip install -r requirements.txt pytest respx  && pytest tests/ -v
```

## ⚠️ מה כן נבדק בפועל, ומה לא (שקיפות מלאה)

| רכיב | סטטוס אימות |
|---|---|
| קוד Python של שני השירותים | ✅ **נבדק בפועל** — 10/10 pytest עוברים |
| Dockerfile | ⚠️ נכתב ונסקר ידנית; **לא בוצע `docker build`** בסביבת ההכנה (אין Docker daemon זמין שם) |
| Helm templates | ⚠️ נכתבו ונסקרו ידנית לתקינות syntax; **לא בוצע `helm template/lint`** בפועל |
| Terraform HCL | ⚠️ נכתב ונסקר ידנית; **לא בוצע `terraform validate`** בפועל |
| YAML (values, ArgoCD, Chart.yaml) | ✅ **נבדק** — `yaml.safe_load` עבר על כל הקבצים |

מומלץ להריץ `helm lint helm/catalog-api` ו-`helm template ... | kubectl
apply --dry-run=client -f -` לפני כל שימוש אמיתי — זה הצעד הראשון שהייתי
מבצע בעצמי ברגע שיש לי סביבה עם Docker/Helm/Terraform מותקנים.

## מסמכים נלווים

- [`docs/DECISIONS.md`](docs/DECISIONS.md) — החלטות, חלופות שנשקלו, ופשרות
- [`docs/SECRETS.md`](docs/SECRETS.md) — זרימת ניהול הסודות המלאה
# devops-poc
