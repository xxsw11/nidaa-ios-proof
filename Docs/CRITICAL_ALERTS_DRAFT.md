# Critical Alerts — مسودة فقط، لم تُقدّم

28 سبتمبر 2026. الحالة **Awaiting approval**. راجعت وثائق Apple الرسمية في هذه الجولة. الاستحقاق الخاص يسمح بطلب إذن المستخدم للتنبيه الحرج الذي قد يتجاوز الصامت وDo Not Disturb؛ لا تكفي إضافة اسم entitlement للملف دون منحه ودون توقيع يدعمه وإذن المستخدم. [وثيقة entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts)، [criticalAlert authorization](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/criticalalert).

لم يوضع الاستحقاق الحرج في أي إعداد أو ملف توقيع، ولا يطلب المصدر `.criticalAlert` ولا يستخدم critical sound أو interruption level حرج. سيُختبر الإشعار العادي فقط إلى أن تُمنح صلاحية مناسبة. تجاوز الصامت **غير مثبت**.

[نموذج طلب Apple](https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/) أعاد توجيهًا إلى تسجيل الدخول؛ لم نرَ حقوله الحالية ولم نُدخل بيانات أو نُرسل طلبًا. هذه مواد تحضير وليست قائمة حقول إلزامية من Apple. أهلية الاستخدام والقرار لدى Apple؛ لا ضمان قبول. [طلبات القدرات المدارة](https://developer.apple.com/help/account/capabilities/capability-requests).

## معلومات يلزم استكمالها محليًا قبل التقديم

| العنصر | الحالة |
|---|---|
| صاحب الحساب/الجهة القانونية وقناة اتصال مصرح بها | لم تُقدم |
| Team ID وBundle ID النهائي للطلب | لم تُقدما؛ لا معرفات مختلقة |
| عضوية الفريق ومقدم الطلب المخول | غير متحقق منها |
| سياسة الاستخدام الجدي والموافقة والسحب والحد من الإساءة | تصميم محفوظ في v06؛ يلزم تنفيذه فعليًا قبل وصفه كقدرة مكتملة |
| إثبات إشعار عادي على iPhone بالصامت وFocus | Not tested |
| وصف الفجوة التي لا يحلها الإشعار العادي | يُستكمل بالأدلة؛ لا نتيجة مفترضة |
| إثبات تحكم المستخدم وإيقاف التنبيه وحدود الصوت | غير مثبت أصليًا؛ لا وعد بتحكم كل المخارج |
| فيديو/لقطات جهاز واختبارات وبيانات خصوصية | غير متوفرة بعد |

## مسودة عربية للمراجعة

نداء مشروع تواصل مساند يهدف إلى إظهار طلب مساعدة عند خطر جدي بين أشخاص وافقوا صراحة على استقبال نداءات من دائرة محددة. لا يُقدّم كجهة طوارئ رسمية ولا كضمان وصول أو استجابة.

نطلب تقييم أهلية استخدام Critical Alerts للحالات الجدية التي قد لا يكون فيها الإشعار العادي كافيًا أثناء الصامت أو Focus. ما زلنا في إثبات تقني محدود؛ لم نثبت تجاوز الصامت ولم تُمنح لنا صلاحية التنبيهات الحرجة. سنرفق نتائج أجهزة فعلية ووصف القصور المقاس قبل تقديم الطلب النهائي.

التصميم المقصود يتضمن تحققًا محليًا قبل الإرسال، فعلًا مقصودًا، موافقة مستقلة لكل شخص، سحب الإذن، إيقاف التنبيه، وفصل تأكيد الجهاز عن القبول البشري. هذه ضوابط تصميم، وليست كلها منفذة في إثبات iPhone الحالي. لا يُستخدم التنبيه الحرج للإعلانات أو الرسائل العادية أو محاكاة المكالمات. سيعتمد الاستخدام على موافقة Apple ثم إذن المستخدم وعلى تطبيق ضوابط السلامة والخصوصية والتحقق منها.

## English application draft

NIDAA is a supplementary communication project for serious-danger requests within an explicitly consented trusted-contact circle. It is not an official emergency service and does not guarantee delivery or human response.

We request an assessment of eligibility for Critical Alerts where ordinary notifications may be insufficient during Silent mode or Focus. We are currently preparing a limited native technical proof. We have not demonstrated silent-mode bypass or received the entitlement. Physical-device findings and the measured limitations of ordinary notifications will accompany a finalized request.

The intended product safeguards include fresh local authentication before sending, a deliberate send action, per-contact consent and revocation, user control to stop alerts, and separate device-observation and human-response states. These are design commitments; they are not all implemented in the current native proof. Critical Alerts would not be used for advertising, routine messages, continuous silent audio, or sham calls. Any implementation would depend on Apple's approval, the user's permission, and verified safety and privacy controls.

Account identity, authorized applicant, app identifiers, device evidence, and final policies remain to be supplied and reviewed before submission.

## بعد الموافقة فقط

تحقق من منح الاستحقاق للفريق وApp ID، أعد provisioning، ثم أضف إعدادًا معزولًا موثقًا يطلب الإذن الحرج ويختبره على جهاز مخول. لا تغيّر المسار المحلي افتراضيًا. سجل حالات رفض الإذن وسحبه والعودة للإشعار العادي. لا تُضف حيل خلفية، أو صوتًا صامتًا مستمرًا، أو PushKit لمكالمات غير حقيقية. لا ادعاء بتحكم في الصامت أو الكشاف أو كل السماعات دون دعم رسمي وإثبات منفصل.
