# מסמך החלטות — חלק 1 (On-Hands טכני)

## 1. שני microservices, לא אחד
**החלטה:** `catalog-api` (פנימי בלבד) + `orders-api` (היחיד שנחשף החוצה).
**למה:** המטלה דורשת הדגמה גם של ערוצים פנימיים וגם חיצוניים — קשה
להדגים הבדל אמיתי (NetworkPolicy, Ingress, SLA) עם שירות בודד.
**חלופה שנשקלה:** שירות יחיד עם שני endpoints "פנימי"/"חיצוני" באותו
Deployment — נדחתה כי זה לא מדגים הפרדת NetworkPolicy/scaling אמיתית
ברמת workload.

## 2. Namespaces משותפים בקלאסטר יחיד (לא קלאסטרים נפרדים)
**החלטה:** dev/staging/prod = namespaces נפרדים, לא קלאסטרים נפרדים.
**למה:** בעלות תפעולית נמוכה יותר (upgrade/patch של control plane פעם
אחת, לא פעמיים-שלוש), ומספיק Isolation בפועל כש-RBAC+NetworkPolicy+
ResourceQuota+PSA אוכפים גבול אמיתי (כפי שממומש ב-Terraform module).
**חלופה שנשקלה:** קלאסטרים נפרדים לחלוטין — עדיפה בארגון גדול יותר או
כשיש דרישת regulatory לבידוד פיזי מלא (למשל prod חייב להיות ב-VPC/
subscription נפרד). ציינתי ב-`terraform/environments/*/main.tf` שהמעבר
דורש שינוי `config_context` בלבד — המודול עצמו לא משתנה.
**פשרה:** אם דרישת isolation תתחדד (compliance), המעבר לקלאסטרים נפרדים
זול בזכות המודול המשותף, אבל היום נבחר הפתרון הזול יותר לתחזוקה.

## 3. הפרדת CI מ-CD דרך Git, לא דרך kubectl ב-Jenkins
**החלטה:** Jenkins בונה/בודק/סורק/דוחף image, ומבצע git commit לעדכון
tag — **אף פעם לא** `kubectl apply`. ArgoCD (in-cluster) הוא שמסנכרן.
**למה:** Jenkins לא צריך אף credential לקלאסטר בכלל — צמצום משמעותי של
blast radius אם ה-CI נפרץ. גם עקבי עם עקרון GitOps: Git = single source
of truth.
**פשרה:** לופ פידבק איטי יותר (git commit → ArgoCD poll/webhook → sync)
לעומת `kubectl apply` ישיר — קביל, כי המטרה היא אמינות לא מהירות מרבית.

## 4. Auto-sync ל-dev/staging, Manual-only ל-prod
**החלטה:** שני ApplicationSets נפרדים (לא אחד עם תנאי) — prod תמיד דורש
`argocd app sync` יזום.
**למה:** self-heal אוטומטי ל-prod מסוכן — אם מישהו מבצע hotfix ידני
דחוף בקונסולה בזמן תקרית, ArgoCD "יתקן" את זה בחזרה תוך דקות בלי אזהרה.
**חלופה שנשקלה:** `syncPolicy.automated` עם `syncWindows` מוגבלים לשעות
עבודה — נדחתה כי עדיין לא פותרת את בעיית ה-hotfix.

## 5. אסימטריה בין SAST (soft-fail) ל-Trivy image scan (hard-fail)
**החלטה:** ממצאי pip-audit/bandit מתועדים אך לא חוסמים build; Trivy
HIGH/CRITICAL כן חוסם (`--exit-code 1`).
**למה:** בריפו עם חוב טכני קיים (כמו המתואר בתרחיש חלק 2), hard-fail
מיידי על SAST מלמד צוותים לעקוף CI. עלות התיקון ל-CVE ב-base image
נמוכה (bump גרסה) מול סיכון גבוה (image ידוע כפגיע) — יחס עלות/סיכון
שונה לגמרי.
**Roadmap:** אחרי 1-2 ספרינטים לניקוי חוב קיים, SAST HIGH/CRITICAL עובר
גם הוא ל-hard-fail.

## 6. Versioning: Immutable tags (`<sha>-<build>`), לא `latest`
**למה:** `latest` הופך rollback לבלתי-דטרמיניסטי — אי אפשר לדעת בוודאות
איזה קוד רץ. Semantic Versioning (`vX.Y.Z`) נשמר לרמת ה-Chart
(`Chart.yaml appVersion`), לא לתיוג image אוטומטי בכל commit.

## 7. Blue/Green/Canary — לא ממומש ב-Deployment הבסיסי, מוצא כ-Argo Rollouts
**למה:** מיזוג rollout strategy מתקדמת (traffic shifting הדרגתי) לתוך
`Deployment` רגיל דורש שכבת ניתוב נוספת בכל מקרה (Service mesh/Argo
Rollouts CRD) — עדיף להפריד את זה משכבת ה-workload הבסיסית כדי שכל
שירות יכול לבחור rolling/canary/blue-green בלי לשנות את ה-chart shape.
**מגבלת POC:** לא מומש בפועל בזמן שהוקצב — מתועד כהחלטת ארכיטקטורה
ל-iteration הבאה.

## 8. Secrets: Vault+ESO ל-runtime, Jenkins Credentials ל-CI (לא אותו dinner)
ר' פירוט מלא ב-`docs/SECRETS.md` — שני מחזורי חיים שונים לגמרי, נפתרים
בשני מנגנונים שונים בכוונה.

## הנחות עבודה כלליות שהובילו להחלטות
- קלאסטר יחיד משותף (לא multi-cloud), Container Registry פרטי קיים.
- Vault כבר פרוס וזמין עם Kubernetes Auth Method מופעל (bootstrap
  חד-פעמי מחוץ לסקופ).
- זמן שהוקצב לחלק זה (~4 שעות לפי לוח הזמנים) לא הספיק ל-`docker
  build`/`helm template`/`terraform validate` בפועל בסביבת ההכנה
  (ראו מגבלת sandbox ב-README) — עדיפות ניתנה לקוד עובד ונבדק
  (Python/pytest) ולעומק ההחלטות על פני כיסוי הרצה מלא של כל השכבות.
