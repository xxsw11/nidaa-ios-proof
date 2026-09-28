# معمارية المرحلة المحلية الحالية

ExperienceRoot يعرض تبويبات SwiftUI ويمرر الحالة إلى ExperienceStore. يتولى Store تنسيق المصادقة ودورة حياة التطبيق والمظهر والتفضيلات؛ لا ينفذ إرسالًا حقيقيًا. LocalSimulation وSendGate داخل ProofCore يفرضان الموافقة، الربط بين التحقق والمستلمين والنوع، الاستخدام الواحد والمهلة، ومنع الحالات غير الصالحة والتكرار.

AlertRepository يحفظ جهات العرض والنداءات والأحداث بملف Foundation ذري ذي مخطط إصدار 2 وحماية iOS كاملة. DemoPreferences يحفظ المظهر وخيار القفل ويقرأ جهات النسخة السابقة للهجرة الأولى فقط؛ توجد PrivacyInfo.xcprivacy بسبب التفضيلات. AlertActionGate يربط تفويض إعادة المحاولة/الإضافة بالمُعرّف والفعل والمستقبلين وحالتهم ومدة 15 ثانية واستخدام واحد. لا تُسلسل أي بوابة تحقق. راجع [تفاصيل الاستعادة](LOCAL_STABILIZATION.md). الحزمة Swift مستقلة عن SwiftUI ولا تحتوي شبكة أو مزود إرسال. لا تبعيات جديدة.

LocalAuthenticationService يقدم تحقق النظام الفعلي عند استخدامه، مع وصف مختلف للبديل. محاكاة المصادقة تحت شرط Debug وSimulator فقط، بوسم مرئي؛ XCTests لا تثبت العتاد. قفل التطبيق منفصل عن بوابة إنشاء النداء.

ProofView وProofStore أدوات تقنية محفوظة في مسار إعدادات منفصل. كل جدولة إشعار أو تسجيل APNs محجوب بواسطة ExecutionScope في جميع التكوينات الحالية. الشرح التاريخي أدناه يخص مسار الإثبات السابق ولا يجيز إعادة تفعيله ضمن هذه المرحلة.

## مرجع تاريخي — فصل مسؤوليات الإثبات السابق

# حدود الإثبات وفصل المسؤوليات

```text
ProofView (SwiftUI)
  → ProofStore (MainActor, commands and current session)
      → LocalAuthenticationService → LocalAuthentication
      → NotificationService / NotificationDelegate → UserNotifications
      → RemoteRegistrationService → UIApplication / APNs registration only
      → ProofCore (window rules and independent evidence fields)

Apple Push Notifications Console → APNs → authorized iPhone
Provider acceptance evidence: external test worksheet
Device-to-server acknowledgment: Not enabled
Human response: explicit local test action only
```

لا تستدعي الواجهة SDK للمصادقة أو جدولة الإشعار مباشرة؛ تجمع النتيجة في Store. يستدعي زر اختبار واحد تحققًا جديدًا بنظام الجهاز؛ لا PIN مخصص ولا حفظ نجاح كجلسة إرسال عامة. انقطاع التطبيق للخلفية يبطل التحقق الجاري، ويفحص المنسق نافذة الاختبار مجددًا قبل الجدولة وبعدها؛ لا يكرر محاولة فاشلة تلقائيًا.

نموذج الأدلة لا يستخدم حالة واحدة مثل delivered لثلاثة معانٍ. `locallyScheduledAt` قبول جدولة على الجهاز، و`providerAcceptedAt` مخصص لمحول مزود موثق لكنه غير متصل في هذه النسخة؛ و`observedAt/observation` يسجلان أصل الرصد المحلي؛ و`humanRespondedAt` نتيجة زر مستقل مع تحقق، بعد رصد وداخل الصلاحية ودون إلغاء. لا يُستنتج وصول من الجدولة أو من تسجيل رمز APNs.

يُثبّت UNUserNotificationCenterDelegate عند بدء AppDelegate لضمان عدم إهمال رد فتح الإشعار عند التشغيل البارد. لا يمنع الاستقبال بشرط مصادقة؛ المصادقة للإجراءات المقصودة. يُميز remote بواسطة UNPushNotificationTrigger الفعلي، لا بحقل يدعي نوع الرسالة. الحمولة تقبل علامة الإثبات وUUID وتاريخ انتهاء فقط؛ لا تفسير HTML أو أوامر.

النافذة سجل تشغيل محلي محدود بساعتين وليست حد تفويض إنتاجيًا. يمكن إلغاء المعلّق من التطبيق، لكن المنصة تتحكم في العرض والصوت خارج الواجهة. المرُسل الخارجي مسؤول عن الجهاز والنافذة والانتهاء. الشريط السفلي يلغي الاختبار المحلي ولا يدعي تحكمًا مباشرًا في صوت النظام أو سحب رسالة APNs.

الخصوصية: لا حسابات أو دفتر عناوين أو موقع أو ميكروفون أو صور أو ملفات أسرار. لا مكاتب تحليلات. نافذة الاختبار والأحداث والرمز في الذاكرة فقط، ولا تقرأ NSUserDefaults. يمنع إدخال أسماء الأسرة؛ يستخدم جهازًا مستعارًا ورسائل اختبار عامة. الأدلة اليدوية PrivateEvidence خارج الحزمة وGit.

لا اعتماد تشغيل خارجي: SwiftUI/UIKit وLocalAuthentication وUserNotifications من Apple، Foundation وCombine وحزمة ProofCore محلية. لا تغيير لترخيص الأطر؛ استخدام Xcode/SDK يخضع لشروط Apple. لم ننقل كودًا من مكتبات خارجية أو عينات مرخصة؛ الكود مخصص للإثبات. مراجعة المكونات لم تجد حاجة لـFirebase أو Flutter أو مولد مشروع خارجي.

الواجهة عربية وRTL بأحجام نص النظام وعناصر Form وأزرار 44 نقطة أو أكثر وشريط إيقاف ثابت؛ تلك خيارات مصدر، وليست نتيجة اختبار VoiceOver أو Dynamic Type أو معاينة SwiftUI فعلية. لا صورة متصفح تُقدم كصورة تطبيق iOS.

اللون الأصفر والأسود محفوظ في شاشة الإثبات. تخصيص v06 الكامل لا يزال مرجع المنتج دون تعديل؛ نقله الأصلي الكامل خارج نطاق إثبات التنبيه الحالي.

مراجع التنفيذ: [سياسة التحقق ورمز الجهاز](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication)، [LAContext وFace ID usage description](https://developer.apple.com/documentation/localauthentication/lacontext)، [الإشعار المحلي](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)، [delegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate).
