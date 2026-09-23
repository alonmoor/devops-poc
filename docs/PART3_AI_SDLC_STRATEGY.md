# חלק 3 — אסטרטגיית טרנספורמציה ל-AI SDLC

מסמך אסטרטגי להצגה בפני הנהלה וצוותי פיתוח. הקשר ארגוני: ~60 מפתחים, 8 צוותים, תשתית
Kubernetes לא אחידה (חלק עובדים ישירות מול הקלאסטר, חלק עם Helm chart פרטי משלהם).

## 1. מיפוי שלבי ה-SDLC והזדמנויות ל-AI

| שלב | כאב קיים | הזדמנות AI קונקרטית |
|---|---|---|
| תכנון/Backlog | פירוק task לא אחיד בין צוותים | סיכום/פירוק issue אוטומטי + זיהוי תלויות בין צוותים |
| כתיבת קוד | זמן context-switch גבוה, קוד boilerplate חוזר | Coding agent (autocomplete + agentic tasks מרובי-קבצים) |
| Code Review | תור review ארוך, חוסר עקביות בסטנדרטים בין 8 צוותים | סוכן review ראשוני שבודק סטנדרטים אובייקטיביים לפני reviewer אנושי |
| בדיקות | כיסוי בדיקות לא אחיד | הצעת unit tests אוטומטית לקוד חדש/משתנה |
| תיעוד | README/API docs מיושנים כרונית | Skill ליצירת/עדכון תיעוד API מתוך קוד בפועל (לא הפוך) |
| תחזוקה | ניתוח incident איטי, חיפוש ידני בלוגים | סוכן ניתוח לוגים לאיתור root-cause ראשוני |
| תשתית כקוד (Helm/K8s manifests) | **אין מדיניות ארגונית אחידה ל-RBAC/Namespaces/Resources** (התרחיש הנתון) | סוכן ביקורת Helm/manifest מול Best Practices ו-RBAC לפני מיזוג — ר' סעיף 3 |

השורה האחרונה היא הפער הכי חמור וקונקרטי בתרחיש הנתון (חוסר סטנדרטיזציה, ריצה "מלמטה למעלה"
ללא בעלות ברורה) — ולכן היא הדוגמה שנבחרה לפיתוח מלא בסעיף 3.

## 2. השוואת כלים

| כלי | חוזק | חולשה בהקשר הזה |
|---|---|---|
| **Claude Code** | Agentic אמיתי: מריץ פקודות, קורא פלט אמיתי, מאמת לפני שממשיך (לא רק autocomplete) — מתאים בדיוק למשימות DevOps/K8s שדורשות אינטראקציה עם מערכת חיה | עקומת למידה גבוהה יותר ממתקן autocomplete פשוט |
| GitHub Copilot | פריסה זולה ומהירה ל-60 מפתחים, אינטגרציה IDE חלקה | בעיקר autocomplete — פחות מתאים למשימות agentic מרובות-שלבים כמו ביקורת תשתית |
| Cursor | חוויית IDE ייעודית ל-AI-first workflow | כלי נוסף להטמיע/לתחזק לצד הסביבה הקיימת; ערך מוסף שולי מעבר ל-Copilot לרוב הצוותים |

**המלצה:** לא "כלי אחד לכולם". **Claude Code** כברירת מחדל לפיתוח Agents/Skills פנימיים
ולמשימות DevOps/K8s (הוכח כאן, בפרויקט הזה עצמו, שהוא מסוגל לנהל דיבוג תשתית אמיתי,
לאמת פלט בפועל ולא להניח הצלחה) + **Copilot** לכלל 8 הצוותים ככלי יומיומי זול ב-IDE.
Cursor — אופציונלי, לא ארגוני, לצוותים שמבקשים זאת מפורשות.

## 3. דוגמה קונקרטית: סוכן ביקורת Helm/K8s Manifest (PR Bot)

**קלט:** diff של PR שנוגע ב-helm/**, platform/** או קבצי manifest של K8s, בתוספת baseline
מדיניות ארגונית (RBAC least-privilege, NetworkPolicy חובה, resource requests/limits חובה,
איסור latest כ-image tag, איסור הרצה תחת default ServiceAccount).

**פלט:** תגובת PR מובנית — רשימת ממצאים לפי חומרה (blocking / warning), עם הצעת תיקון.

**אינטגרציה:** CI Check (GitHub Actions/Jenkins stage) שרץ על כל PR שנוגע בנתיבים הרלוונטיים,
מפרסם תגובה כ-PR bot, וחוסם מיזוג רק על ממצאי blocking — באותה פילוסופיית a-symmetric
gate שכבר קיימת בפרויקט הזה (Trivy hard-fail מול SAST soft-fail, ר' docs/DECISIONS.md).

**פסאודו-קוד:**

    on pull_request(paths: ["helm/**", "platform/**", "**/*.yaml"]):
        changed = get_changed_k8s_manifests(pr)
        policy  = load_org_policy_baseline()   # RBAC / NetworkPolicy / resources / tags

        findings = []
        for manifest in changed:
            findings += check_rbac_least_privilege(manifest, policy)
            findings += check_networkpolicy_present(manifest, policy)
            findings += check_resource_requests_limits(manifest, policy)
            findings += check_image_tag_not_latest(manifest, policy)
            findings += check_no_default_serviceaccount(manifest, policy)

        post_pr_comment(format(findings))
        fail_check() if any(f.severity == "blocking" for f in findings) else pass_check()

זו בדיוק סוג הבעיה שהתגלתה בפועל בפרויקט הזה עצמו (NetworkPolicy פתוחה לחלוטין על
PostgreSQL, אותרה בביקורת ידנית) — ההצעה היא להזיז את הגילוי הזה משלב ביקורת תקופתית
ידנית לשלב ה-PR, לפני מיזוג.

## 4. מתודולוגיה ותיעוד

Playbook פר Agent/Skill (חוזה קלט/פלט, מגבלות ידועות, נתיב escalation) נשמר ב-repo ייעודי
ai-playbooks/, מנוהל כקוד (code review, גרסאות). בדיקת "טריות" תיעוד — CI check פשוט
שבודק שה-playbook עודכן יחד עם שינוי לוגיקת הסוכן. Onboarding — מודול קצר בתהליך הקליטה
הקיים + מפגש pairing עם "Champion" צוותי בשבוע הראשון.

## 5. רתימת מפתחים ושינוי תרבותי

**התנגדויות צפויות:** חשש מהחלפה, חשש מאובדן שליטה על קוד קריטי (במיוחד שינויי תשתית),
ספקנות לגבי נכונות הסוכן בהקשרי אבטחה.

**תכנית:** Champion אחד לכל אחד מ-8 הצוותים (משוב חי לתוך ה-playbook המרכזי); הדרכות
hands-on על items אמיתיים מה-backlog (לא הרצאה); מדידת Adoption (% PRs רלוונטיים שעברו
דרך הסוכן, % הצעות שאומצו); וגבול אמון מפורש וגלוי — הסוכן אף פעם לא ממזג/מיישם אוטומטית,
רק מציע ומעיר (אותו עיקרון שנשמר לאורך כל הפרויקט הטכני הזה — הצעה, אימות אנושי, ואז ביצוע).

## 6. בקרות ואבטחת מידע

- ללא שליחת סודות/קניין רוחני לספק AI חיצוני בלי הסכם no-training-on-data ברמת enterprise.
- קוד מיוצר עובר את אותו SAST/license-scan כמו כל dependency אחר.
- Code Review אנושי נשאר חובה לכל שינוי — פלט הסוכן הוא קלט ל-review, לא תחליף לו.
- הרשאות טכניות: ברירת מחדל read-only/PR-comment בלבד; כל יכולת write (auto-fix commit)
  דורשת opt-in מפורש פר-repo ומשאירה audit trail.
- קטלוג Agents/Skills עובר סקירת אבטחה לפני זמינות כללית (מקביל לעיקרון Trivy gate הקיים).

## 7. תכנית הטמעה מדורגת

| שלב | היקף | משך | מדידה |
|---|---|---|---|
| Pilot | צוות אחד, סוכן ביקורת manifest בלבד | 4 שבועות | false-positive rate, זמן-ל-review |
| הרחבה | 2-3 צוותים נוספים עם בעלות Helm קיימת | 4-6 שבועות | עדכון baseline מדיניות מהפידבק |
| Scale | יתר 5 הצוותים + Copilot ארגוני כללי | 6-8 שבועות | Adoption, champions מאוישים |
| מתמשך | הרחבת קטלוג (log-analysis agent, API-doc skill) | — | ROI רבעוני |

סה"כ ~4-5 חודשים להטמעה מלאה — תואם לאופק "רבעון עד שניים" שההנהלה ציפתה לו.

## 8. מדדי הצלחה ו-ROI

- **מהירות:** זמן ממוצע PR-open→merge למניפסטים K8s, לפני/אחרי.
- **איכות:** מספר תקריות production שמקורן בפער RBAC/NetworkPolicy/resource-limits שהוחמץ
  (baseline: הממצא האמיתי שאותר בביקורת הידנית בפרויקט הזה עצמו).
- **אימוץ:** % PRs רלוונטיים שעברו דרך הסוכן; % הצעות שאומצו בפועל.
- **עלות:** שעות מפתח נחסכות (אומדן סקר + מדגם ידני מול אוטומטי) מול עלות רישוי/תשתית הכלים.
