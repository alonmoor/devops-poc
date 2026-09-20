# ניהול סודות — Vault + External Secrets Operator

מסמך זה מסביר את זרימת הסודות המלאה, ומבחין במפורש בין שני סוגי סודות
שונים לגמרי מבחינת מחזור החיים שלהם — כפי שהמטלה מבקשת.

## שני סוגי סודות — ולמה הם לא אותו דבר

### 1. סודות בזמן CD/CI (Build-time)
דוגמה: `registry-creds` ב-`Jenkinsfile` (credentials ל-push ל-Container
Registry).

- **מי צורך אותם:** תהליך ה-CI עצמו (Jenkins agent), לא ה-Pod הרץ בייצור.
- **איפה הם חיים:** ב-Jenkins Credentials Store (מוצפן, גישה מבוקרת
  per-pipeline), *לא* ב-Vault.
- **למה לא Vault:** Jenkins כבר צריך auth ל-Vault/Registry בכל מקרה כדי
  להריץ pipeline; הוספת עוד שכבת אינדיירקשן (Jenkins→Vault→Registry)
  לא מוסיפה אבטחה משמעותית לסוד שממילא חי רק בזיכרון האג'נט למשך ריצת
  ה-build, ומייקרת את הארכיטקטורה. Vault שמור לסודות ברמת ה-Runtime
  (ראו למטה) שבהם יש ערך אמיתי לרוטציה דינמית וגישה לפי זהות workload.
- **עקרון מפתח:** הסוד **אף פעם לא נכתב לקובץ בריפו**, לא ל-Helm
  values, ולא ל-log — `withCredentials` ב-Jenkins מזריק אותו כמשתנה
  סביבה חי רק בתוך ה-`sh` block שמשתמש בו, ו-Jenkins מסנן אותו אוטומטית
  מפלט ה-log.

### 2. סודות ברמת ה-Runtime (סודות אפליקטיביים)
דוגמה: `DB_PASSWORD`, `API_SIGNING_KEY` שכל אחד מ-`catalog-api` ו-
`orders-api` צריכים כדי לרוץ.

- **מי צורך אותם:** ה-Pod עצמו, בזמן ריצה, לאורך כל חיי ה-Deployment.
- **איפה הם חיים:** Vault (KV v2), נשלפים ע"י External Secrets Operator
  (ESO) ומוזרקים כ-Kubernetes Secret רגיל שה-Pod צורך דרך `envFrom`.
- **למה Vault + ESO ולא Kubernetes Secret ידני:** רוטציה. אם סוד מתחלף
  ב-Vault, ESO מרענן את ה-`Secret` תוך `refreshInterval` (שעה, בקונפיגורציה
  כאן) *בלי* שאף אחד יריץ `kubectl apply` או ייגע ב-Git — לעומת סוד
  שנכתב ידנית שדורש עדכון ידני בכל סביבה בכל רוטציה.

## זרימת ההזרקה המלאה (Runtime secrets)

```
Vault (KV v2, secret/data/<env>/<service>)
   │
   │  1. Vault Kubernetes Auth validates the ExternalSecret's
   │     ServiceAccount token via TokenReview — no static
   │     credential stored anywhere.
   ▼
SecretStore  (platform/secretstore.yaml — one per namespace,
              owned by platform team, not by app teams)
   │
   │  2. references a Vault role whose policy is scoped to
   │     exactly secret/data/<THIS environment>/* — enforced
   │     Vault-side, so a compromised dev pod cannot read a
   │     prod secret even if k8s RBAC were misconfigured.
   ▼
ExternalSecret  (helm/<service>/templates/externalsecret.yaml —
                 owned by the app team, per-service)
   │
   │  3. pulls db_password / api_signing_key from the path in
   │     values-<env>.yaml, creates/refreshes a native k8s Secret.
   ▼
Kubernetes Secret  "<service>-secret"
   │
   │  4. consumed via envFrom in the Deployment (never mounted
   │     as a file that could be captured by a misconfigured
   │     log shipper or volume snapshot).
   ▼
Running Pod (env vars in-memory only)
```

## מה זה *לא* חושף, ולמה זה חשוב

- **Helm values files (`values-*.yaml`)** מכילים רק את ה-**נתיב** ב-Vault
  (`secret/data/prod/catalog-api`) — לעולם לא את התוכן. ניתן לעשות
  `git blame`/`git log -p` על כל היסטוריית הריפו בלי לחשוף אף סוד.
- **Jenkins logs** לא רואים סוד runtime בכלל — Jenkins לא נוגע בהם;
  הזרימה כולה קורית בתוך הקלאסטר, אחרי שה-Pod כבר רץ.
- **RBAC אנושי** (ראו `terraform/modules/namespace/main.tf`) מאפשר
  ל-`Role` הכי רחב (dev) רק `list` על `secrets` — לראות שסוד קיים, לא
  `get` את הערך. אף role אנושי, באף סביבה, לא יכול לקרוא סוד ישירות.

## הנחת עבודה מוצהרת

מניחים כאן Vault פרוס וזמין בענן/on-prem עם ה-Kubernetes Auth Method
כבר מופעל ברמת ה-cluster (מחוץ לסקופ של ה-POC הזה — זו פעולת bootstrap
חד-פעמית ברמת הפלטפורמה, לא ברמת שירות בודד).
