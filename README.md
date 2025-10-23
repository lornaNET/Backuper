

🚀 Backuper (Unified Launcher) + Uptime Kuma Add-on

Fork از erfjab توسط Lorna (lornaNET) 💙

اسکریپت یکپارچه و هوشمند برای بکاپ‌گیری و ری‌استور خودکار سرویس Uptime Kuma
به‌همراه پشتیبانی از منوی اصلی پروژه‌ی ارژینال ErfJab و قابلیت ارسال بکاپ به تلگرام.
یک ابزار سبک، تمیز، و تمام‌خودکار برای مدیریت ساده‌ی بکاپ‌ها در سرورهای Docker.

<p align="center">
  <b>bash</b> · <b>docker</b> · <b>uptime-kuma</b> · <b>sqlite-safe</b> · <b>telegram notify</b>
</p>
---

🌟 ویژگی‌ها

✅ اجرای منوی اصلی Backuper ارژینال
✅ بکاپ و ری‌استور خودکار برای Uptime Kuma
✅ تشخیص خودکار کانتینر و ولوم /app/data
✅ انتخاب هوشمند آخرین بکاپ (بدون نیاز به وارد کردن مسیر)
✅ ارسال خودکار بکاپ به تلگرام (اختیاری)
✅ قابلیت نصب و حذف سریع لانچر در /usr/local/bin
✅ نگهداری تعداد مشخصی بکاپ (Retention)
✅ سازگار با docker run و docker compose


---

🧠 کاربرد اسکریپت

این اسکریپت به‌صورت خودکار:

1. کانتینر Uptime Kuma را پیدا می‌کند.


2. قبل از بکاپ، در صورت نیاز آن را Stop می‌کند تا دیتابیس SQLite ایمن بماند.


3. از مسیر /app/data درون کانتینر بکاپ گرفته و فایلی مثل
uptime-kuma-20251023-212204.tar.gz می‌سازد.


4. بکاپ را در مسیر /var/backups/uptime-kuma ذخیره می‌کند.


5. می‌تواند آن را به تلگرام بفرستد.


6. هنگام ری‌استور، خودش آخرین فایل را پیدا و بازنویسی می‌کند.


7. در پایان کانتینر را دوباره Start می‌کند.




---

⚙️ نصب سریع اسکریپت

> نیازمندی‌ها: bash, curl, docker



sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/lornaNET/Backuper/main/Backuper.sh)"

برای نصب دائمی لانچر در مسیر /usr/local/bin:

sudo ./Backuper.sh install
# اجرا:
sudo lornaNET


---

🧭 منوی اصلی

=======  Backuper Menu [v1.2.1]  =======
1) Run ORIGINAL Backuper (erfjab)
2) Uptime Kuma Backup
3) Uptime Kuma Restore
0) Exit


---

💾 بکاپ‌گیری از Uptime Kuma

sudo lornaNET kuma-backup

یا از طریق منو → گزینه 2

مسیر ذخیره: /var/backups/uptime-kuma

نام فایل: uptime-kuma-YYYYMMDD-HHMMSS.tar.gz



---

♻️ ری‌استور هوشمند

# آخرین بکاپ به صورت خودکار:
sudo lornaNET kuma-restore

# یا با نام فایل (بدون مسیر):
sudo lornaNET kuma-restore uptime-kuma-20251023-212204.tar.gz

# یا فقط بخشی از نام:
sudo lornaNET kuma-restore 212204

# یا مسیر کامل:
sudo lornaNET kuma-restore /var/backups/uptime-kuma/uptime-kuma-20251023-212204.tar.gz

> در ری‌استور، کانتینر به‌صورت خودکار Stop → Restore → Start می‌شود
و اگر ولوم /app/data نام‌دار باشد، مستقیم داخل آن ری‌استور می‌کند.




---

🐳 نصب و اجرای Uptime Kuma با Docker

🔹 نصب با Docker Compose

mkdir uptime-kuma && cd uptime-kuma
curl -o compose.yaml https://raw.githubusercontent.com/louislam/uptime-kuma/master/compose.yaml
docker compose up -d

> حالا سرویس روی پورت 3001 در دسترس است:
👉 http://0.0.0.0:3001



⚠️ نکته: فایل‌سیستم‌های شبکه‌ای مثل NFS پشتیبانی نمی‌شوند.
حتماً مسیر /app/data را روی دایرکتوری یا Volume محلی مپ کنید.


---

🔹 نصب با Docker Run

docker run -d --restart=always \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  --name uptime-kuma \
  louislam/uptime-kuma:2

> دسترسی:
👉 http://0.0.0.0:3001




---

🔹 حذف کامل Uptime Kuma

برای حذف کامل کانتینر و داده‌ها:

# توقف و حذف کانتینر
docker stop uptime-kuma
docker rm uptime-kuma

# حذف ولوم داده (اختیاری)
docker volume rm uptime-kuma

# اگر از Docker Compose استفاده کردی:
docker compose down -v


---

📤 ارسال بکاپ به تلگرام (اختیاری)

برای فعال‌سازی ارسال بکاپ به تلگرام:

export TELEGRAM_BOT_TOKEN="123456:ABCDEF..."
export TELEGRAM_CHAT_ID="-1001234567890"
export TELEGRAM_MENTION="@lorna_support"
sudo lornaNET kuma-backup

📎 فایل بکاپ مستقیماً در چت تلگرام ارسال می‌شود.


---

⚙️ تنظیمات محیطی

متغیر	پیش‌فرض	توضیح

BACKUP_DIR	/var/backups/uptime-kuma	مسیر ذخیره‌ی بکاپ‌ها
RETENTION	7	تعداد بکاپ‌هایی که نگه می‌مانند
KUMA_CONTAINER_NAME	auto	نام کانتینر Uptime Kuma
KUMA_VOLUME_NAME	auto	نام ولوم /app/data
STOP_DURING_BACKUP	true	توقف موقت کانتینر هنگام بکاپ
KUMA_IMAGE_CANDIDATES	louislam/uptime-kuma:2 louislam/uptime-kuma	ایمیج‌های ممکن برای تشخیص
TELEGRAM_BOT_TOKEN	(خالی)	توکن ربات
TELEGRAM_CHAT_ID	(خالی)	آیدی چت یا کانال
TELEGRAM_MENTION	@lorna_support	منشن در کپشن تلگرام
INSTALL_BIN_NAME	lornaNET	نام لانچر در /usr/local/bin



---

🗑️ حذف اسکریپت از سیستم

sudo lornaNET uninstall
# یا دستی:
sudo rm -f /usr/local/bin/lornaNET


---

🧩 عیب‌یابی سریع

پیام خطا	توضیح

No Uptime Kuma container found	با docker ps -a بررسی کن کانتینر بالا باشه.
Cannot find backup archive	مسیر /var/backups/uptime-kuma رو بررسی کن.
Telegram send failed	توکن یا چت آیدی اشتباهه.


برای دیدن بکاپ‌ها:

ls -lh /var/backups/uptime-kuma


---

📜 مجوز

این پروژه تحت MIT License منتشر شده است.
با آزادی کامل برای استفاده، ویرایش و انتشار مجدد.


---

💙 Credits

Upstream Project: erfjab/Backuper

Uptime Monitor: louislam/uptime-kuma



---

> 🌈 Fork از erfjab توسط Lorna (lornaNET) — با عشق برای بکاپ‌گیری آسان، امن و بدون استرس 💫
