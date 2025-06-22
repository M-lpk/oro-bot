import os
import logging
import sqlite3
import threading
import time
from datetime import datetime, timedelta
from telegram import InlineQueryResultArticle, InputTextMessageContent, InlineKeyboardMarkup, InlineKeyboardButton, ReplyKeyboardMarkup, KeyboardButton, ReplyKeyboardRemove, Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, ConversationHandler, CallbackQueryHandler, InlineQueryHandler
import asyncio
import telegram.error

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

logger.info("Fetching BOT_TOKEN from environment...")
BOT_TOKEN = os.getenv("BOT_TOKEN")
if not BOT_TOKEN:
    raise ValueError("BOT_TOKEN not found in environment variables. Please set it in Railway Environment Variables.")

PRODUCT, SIZE, PHOTO, EDIT, DISCOUNT, CONTACT, SUPPORT, FAQ_STATE, CONFIRM_DISCOUNT = range(9)
OPERATOR_ID = "7695028053"

DISCOUNT_CODES = {
    "oro1": "مهدی", "art2": "مبین", "fac3": "محمد", "nxt4": "مریم", "por5": "نگین",
    "skc6": "مهشید", "drw7": "آیدا", "pix8": "حسین", "cus9": "پویا", "orox": "عرفان"
}

PRODUCTS = {
    "تابلو نخی پرتره (دایره)": {
        "price": "۲,۱۰۰,۰۰۰ تا ۳,۴۰۰,۰۰۰ تومان",
        "thumbnail": "https://i.imgur.com/TDVSaFR.jpeg"
    },
    "تابلو نخی پرتره (مربع)": {
        "price": "بزودی",
        "thumbnail": "https://i.imgur.com/1paKwCQ.png"
    },
    "تابلو نخی شبتاب": {
        "price": "بزودی",
        "thumbnail": "https://i.imgur.com/1paKwCQ.png"
    },
    "تابلو نخی ماندالا": {
        "price": "بزودی",
        "thumbnail": "https://i.imgur.com/1paKwCQ.png"
    }
}

SIZES = {
    "70×70": {
        "price": 2490000,
        "thumbnail": "https://i.imgur.com/BcNC2lo.jpeg"
    },
    "45×45": {
        "price": "بزودی",
        "thumbnail": "https://i.imgur.com/1paKwCQ.png"
    },
    "60×60": {
        "price": "بزودی",
        "thumbnail": "https://i.imgur.com/1paKwCQ.png"
    },
    "90×90": {
        "price": "بزودی",
        "thumbnail": "https://i.imgur.com/1paKwCQ.png"
    }
}

FAQ = {
    "مجموعه oro چیه؟": {
        "answer": "یه گروه از جوون‌های باحال تهران که دارن از هنرشون استفاده می‌کنن. یه تیم خفن که عاشق کارشونه 😎",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    },
    "به شهر منم ارسال می‌کنین؟": {
        "answer": "فعلاً فقط تو شهر تهرانیم! 🏠 ولی داریم نقشه می‌کشیم تا به زودی به تمام نقاط ایران ارسال داشته باشیم. قول می‌دیم زود خبرت کنیم ⏰",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    },
    "تابلو نخی پرتره (دایره) چیه؟": {
        "answer": "بچه‌های هنرمندمون چهره‌ت رو می‌گیرن و با ظرافت تبدیلش می‌کنن به یه تابلو نخی جذاب و بی‌نظیر. یه اثر هنری همراه با خاطره‌ش فقط برای تو 🎨❤️",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    },
    "عکسم باید چه فرمتی باشه؟": {
        "answer": "فقط می‌تونیم عکس ساده تلگرام رو قبول کنیم. بهتره نسبت 1:1 باشه و چهره‌ت کامل بیفته. اگه فرمت دیگه‌ای داری، با پشتیبانی صحبت کن 📲",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    },
    "ادیت عکس چجوریه؟": {
        "answer": "اگه عکست چیز اضافی داره یا مثلاً یه تیکه‌ش خراب شده، فتوشاپ‌کارای ماهرمون رایگان برات درستش می‌کنن. خیالت تخت 🖼️",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    },
    "میتونم مشخصات سفارشم رو عوض کنم؟": {
        "answer": "اگه فرآیند ثبت‌نام کامل شده، با پشتیبانی صحبت کن. وگرنه کافیه /start رو بزنی و از اول شروع کنی 🔄",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    },
    "چقدر طول میکشه تا آماده بشه؟": {
        "answer": "از وقتی سفارشت رو اپراتور تأیید کرد، حداکثر ۳ روز بعد دستته. سریع و آسون ⚡",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    },
    "میتونم چند تا تابلو سفارش بدم؟": {
        "answer": "آره رفیق! 😍 هر چند تا بخوای می‌تونی سفارش بدی. گزینه‌ی 'شروع مجدد' رو بزن و دوباره سفارش بده. فقط حواست باشه سفارشت رو تا آخر تکمیل کنی! 🛒",
        "thumbnail": "https://i.imgur.com/OqrFosV.jpeg"
    }
}

DEFAULT_KEYBOARD = InlineKeyboardMarkup([
    [
        InlineKeyboardButton("شروع مجدد 🎨", callback_data="restart"),
        InlineKeyboardButton("تماس با پشتیبانی 💬", callback_data="support")
    ]
])

DATABASE_PATH = "reminders.db"
running = True

def init_db():
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS reminders
                 (user_id INTEGER, chat_id INTEGER, reminder_type TEXT, remind_at TEXT)''')
    c.execute('''CREATE TABLE IF NOT EXISTS discount_status
                 (user_id INTEGER PRIMARY KEY, extra_discount_eligible BOOLEAN)''')
    conn.commit()
    conn.close()
    logger.info("Database initialized successfully")

def add_reminder(user_id, chat_id, reminder_type, remind_at):
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute("INSERT INTO reminders (user_id, chat_id, reminder_type, remind_at) VALUES (?, ?, ?, ?)",
              (user_id, chat_id, reminder_type, remind_at))
    conn.commit()
    conn.close()
    logger.info(f"Added reminder for user_id: {user_id}, type: {reminder_type}, at: {remind_at}")

def remove_reminders(user_id):
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM reminders WHERE user_id = ?", (user_id,))
    c.execute("DELETE FROM discount_status WHERE user_id = ?", (user_id,))
    conn.commit()
    conn.close()
    logger.info(f"Removed all reminders and discount status for user_id: {user_id}")

def set_extra_discount_eligible(user_id, eligible):
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute("INSERT OR REPLACE INTO discount_status (user_id, extra_discount_eligible) VALUES (?, ?)",
              (user_id, 1 if eligible else 0))
    conn.commit()
    conn.close()
    logger.info(f"Set extra_discount_eligible to {eligible} for user_id: {user_id}")

def get_extra_discount_eligible(user_id):
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute("SELECT extra_discount_eligible FROM discount_status WHERE user_id = ?", (user_id,))
    result = c.fetchone()
    conn.close()
    return bool(result[0]) if result else False

def reminder_loop(application):
    logger.info("Starting reminder loop...")
    while running:
        try:
            conn = sqlite3.connect(DATABASE_PATH)
            c = conn.cursor()
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            c.execute("SELECT user_id, chat_id, reminder_type FROM reminders WHERE remind_at <= ?", (current_time,))
            reminders = c.fetchall()
            logger.info(f"Checked reminders at {current_time}, found {len(reminders)} reminders to send")
            
            for user_id, chat_id, reminder_type in reminders:
                logger.info(f"Scheduling reminder for user_id: {user_id}, chat_id: {chat_id}, type: {reminder_type}")
                try:
                    if reminder_type == "1hour":
                        message = (
                            f"سلام دوست خوبم! 🌟\n"
                            f"ما هنوز منتظریم تا سفارشت رو کامل کنی.\n"
                            f"بیا ادامه بدیم و یه تابلو نخی فوق‌العاده برات بسازیم! 🎨"
                        )
                    elif reminder_type == "1day":
                        message = (
                            f"سلام رفیق عزیز! ✨\n"
                            f"یه روزه که oro منتظرته!\n"
                            f"اگه تا یک ساعت دیگه سفارشت رو تکمیل کنی، ۱۰۰,۰۰۰ تومن تخفیف بیشتر می‌گیری! 🎁\n"
                            f"بیا تمومش کنیم! 💪"
                        )
                        set_extra_discount_eligible(user_id, True)
                    elif reminder_type == "3days":
                        message = (
                            f"سلام دوست عزیز! ⚠️\n"
                            f"موجودی تابلو نخی پرتره (دایره) رو به اتمامه و ممکنه اطلاعات سفارشت پاک بشه!\n"
                            f"تا دیر نشده، همین امروز سفارشت رو کامل کن تا خیالت راحت بشه. 🖼️"
                        )
                    elif reminder_type == "5days":
                        remove_reminders(user_id)
                        message = (
                            f"سفارش شما منقضی شده! 😔\n"
                            f"برای ثبت سفارش جدید، لطفاً دوباره شروع کنید."
                        )

                    async def send_message(context: ContextTypes.DEFAULT_TYPE):
                        try:
                            await context.bot.send_message(
                                chat_id=chat_id,
                                text=message,
                                reply_markup=DEFAULT_KEYBOARD
                            )
                            logger.info(f"Reminder {reminder_type} sent successfully to chat_id: {chat_id}")
                        except Exception as e:
                            logger.error(f"Error sending reminder to chat_id {chat_id}: {e}")

                    application.job_queue.run_once(
                        send_message,
                        when=0,
                        data=None,
                        chat_id=chat_id,
                        name=f"reminder_{user_id}_{reminder_type}"
                    )

                    c.execute("DELETE FROM reminders WHERE user_id = ? AND reminder_type = ?", (user_id, reminder_type))
                    conn.commit()
                except Exception as e:
                    logger.error(f"Error scheduling reminder for chat_id {chat_id}: {e}")
            
            conn.close()
        except Exception as e:
            logger.error(f"Error in reminder loop: {e}")
        
        time.sleep(60)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"Received /start command from user: {update.message.from_user.id}")
    context.user_data.clear()
    context.user_data['current_state'] = PRODUCT
    await update.message.reply_text("سلام! 😊 به oro خوش اومدی")
    await asyncio.sleep(2)
    await update.message.reply_text(
        "🌟 بیا نگاهی به محصولاتمون بنداز 👇",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("محصولات 🎉", switch_inline_query_current_chat="محصولات")],
            [
                InlineKeyboardButton("❓ سوالات پرتکرار", switch_inline_query_current_chat="سوالات"),
                InlineKeyboardButton("💬 تماس با پشتیبانی", callback_data="support")
            ],
            [
                InlineKeyboardButton("📖 درباره ما", callback_data="about_us"),
                InlineKeyboardButton("📷 اینستاگرام", url="https://instagram.com/oro.stringart")
            ]
        ])
    )
    return PRODUCT

async def inlinequery(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    logger.info(f"Received inline query: {update.inline_query.query}")
    query = update.inline_query.query.lower()
    results = []

    if query in ["", "محصولات"]:
        for product, info in PRODUCTS.items():
            results.append(
                InlineQueryResultArticle(
                    id=product,
                    title=product,
                    description=f"💰 رنج قیمت: {info['price']}",
                    input_message_content=InputTextMessageContent(f"{product}"),
                    thumb_url=info['thumbnail'],
                    thumb_width=150,
                    thumb_height=150
                )
            )
    elif query == "سایز":
        for size, info in SIZES.items():
            price = info['price']
            price_display = price if isinstance(price, str) else f"{price:,} تومان".replace(',', '،')
            results.append(
                InlineQueryResultArticle(
                    id=size,
                    title=size,
                    description=f"💰 قیمت: {price_display}",
                    input_message_content=InputTextMessageContent(f"{size}"),
                    thumb_url=info['thumbnail'],
                    thumb_width=150,
                    thumb_height=150
                )
            )
    elif query in ["سوالات", "سوال"]:
        for question, info in FAQ.items():
            results.append(
                InlineQueryResultArticle(
                    id=question,
                    title=question,
                    description="❓ یه سوال پرتکرار",
                    input_message_content=InputTextMessageContent(f"{question}"),
                    thumb_url=info['thumbnail'],
                    thumb_width=150,
                    thumb_height=150
                )
            )
    else:
        results.append(
            InlineQueryResultArticle(
                id="no_results",
                title="نتیجه‌ای یافت نشد",
                description="لطفاً محصولات یا سوالات رو انتخاب کنید.",
                input_message_content=InputTextMessageContent("نتیجه‌ای یافت نشد")
            )
        )

    await update.inline_query.answer(results)

async def handle_product_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"Handling product selection: {update.message.text}")
    message_text = update.message.text
    if message_text in FAQ:
        await update.message.reply_text(FAQ[message_text]['answer'], reply_markup=DEFAULT_KEYBOARD)
        return PRODUCT
    if message_text not in PRODUCTS:
        await update.message.reply_text(
            "لطفاً یه محصول از منو انتخاب کن! 😊\nبا تایپ '@BotUsername محصولات' محصولات رو ببین.",
            reply_markup=DEFAULT_KEYBOARD
        )
        return PRODUCT

    selected_product = message_text
    product_price = PRODUCTS[selected_product]["price"]

    if product_price == "بزودی":
        await update.message.reply_text(
            "متأسفیم، این محصول هنوز آماده نیست! 😔\n"
            "یه محصول دیگه انتخاب کن:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("محصولات 🎉", switch_inline_query_current_chat="محصولات")]
            ])
        )
        return PRODUCT

    context.user_data['product'] = selected_product
    context.user_data['current_state'] = SIZE

    await update.message.reply_text(
        f"{selected_product} انتخاب شد! حالا یه سایز انتخاب کن:",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("انتخاب سایز 📏", switch_inline_query_current_chat="سایز")]
        ])
    )
    return SIZE

async def handle_size_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"Handling size selection: {update.message.text}")
    message_text = update.message.text
    if message_text not in SIZES:
        await update.message.reply_text(
            "لطفاً یه سایز از منو انتخاب کن! 😊\nبا تایپ '@BotUsername سایز' سایزها رو ببین.",
            reply_markup=DEFAULT_KEYBOARD
        )
        return SIZE

    selected_size = message_text
    size_price = SIZES[selected_size]["price"]

    if isinstance(size_price, str) and size_price == "بزودی":
        await update.message.reply_text(
            "متأسفیم، این سایز هنوز آماده نیست! 😔\n"
            "یه سایز دیگه انتخاب کن:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("انتخاب سایز 📏", switch_inline_query_current_chat="سایز")]
            ])
        )
        return SIZE

    context.user_data['size'] = selected_size
    context.user_data['username'] = update.message.from_user.username
    context.user_data['user_id'] = update.message.from_user.id
    context.user_data['current_state'] = PHOTO

    user_id = context.user_data['user_id']
    chat_id = update.message.chat_id

    current_time = datetime.now()
    add_reminder(user_id, chat_id, "1hour", (current_time + timedelta(hours=1)).strftime("%Y-%m-%d %H:%M:%S"))
    add_reminder(user_id, chat_id, "1day", (current_time + timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S"))
    add_reminder(user_id, chat_id, "3days", (current_time + timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S"))
    add_reminder(user_id, chat_id, "5days", (current_time + timedelta(days=5)).strftime("%Y-%m-%d %H:%M:%S"))
    logger.info(f"Reminders added for user_id: {user_id}, chat_id: {chat_id}")

    await update.message.reply_text(
        f"عالیه! 👏\nانتخابت حرف نداره ✨\nپس انتخابت شد: {context.user_data['product']} {selected_size}",
        reply_markup=DEFAULT_KEYBOARD
    )
    await update.message.reply_text(
        "یه نکته بگم: ℹ️\nفعلاً مجموعه oro فقط در شهر تهران فعالیت می‌کنه 🏙️\nولی داریم برنامه‌ریزی می‌کنیم که به زودی همه‌جا باشیم. 🚀",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("✅ فهمیدم", callback_data="understood")]])
    )
    return PHOTO

async def resume_order(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()

    if not context.user_data:
        await query.message.reply_text(
            "به نظر می‌رسه سفارشت پاک شده! 😔 بیا از اول شروع کنیم:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("محصولات 🎉", switch_inline_query_current_chat="محصولات")]
            ])
        )
        return PRODUCT
    elif 'product' not in context.user_data:
        await query.message.reply_text(
            "بیا از اول شروع کنیم! 😊",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("محصولات 🎉", switch_inline_query_current_chat="محصولات")]
            ])
        )
        return PRODUCT
    elif 'size' not in context.user_data:
        await query.message.reply_text(
            "یه سایز انتخاب کن:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("انتخاب سایز 📏", switch_inline_query_current_chat="سایز")]
            ])
        )
        return SIZE
    elif 'photo' not in context.user_data:
        await query.message.reply_text(
            "عکست رو بفرست! 📸",
            reply_markup=DEFAULT_KEYBOARD
        )
        return PHOTO
    elif 'edit' not in context.user_data:
        await query.message.reply_text(
            "نیاز به ادیت داره؟ ✂️",
            reply_markup=ReplyKeyboardMarkup([["بله", "خیر"]], one_time_keyboard=True, resize_keyboard=True)
        )
        return EDIT
    elif 'discount' not in context.user_data:
        await query.message.reply_text(
            "کد تخفیف داری؟ 🎁\nهمینجا برامون بنویس، یا دکمه زیر رو بزن:",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("💸 تخفیف ندارم", callback_data="no_discount")]])
        )
        return DISCOUNT
    elif 'contact' not in context.user_data and not context.user_data.get('username'):
        await query.message.reply_text(
            "لطفاً شماره تلفنتون رو به اشتراک بذارید 📞",
            reply_markup=ReplyKeyboardMarkup(
                [[KeyboardButton("ارسال شماره تلفن 📱", request_contact=True)]],
                one_time_keyboard=True,
                resize_keyboard=True
            )
        )
        return CONTACT
    else:
        await query.message.reply_text(
            "سفارشت تقریباً آماده‌ست! 😊 با پشتیبانی تماس بگیر یا دوباره شروع کن:",
            reply_markup=DEFAULT_KEYBOARD
        )
        return ConversationHandler.END

async def photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info("Entering photo state...")
    if update.callback_query:
        query = update.callback_query
        await query.answer()
        await query.edit_message_text(
            "حله رفیق! حالا وقتشه بترکونیم 💥\n"
            "عکسی که دوست داری به این تابلو نخی تبدیل بشه رو برامون بفرست 📸\n"
            "اگه نسبت 1:1 باشه، نتیجه بهتر میشه! 👍",
            reply_markup=None
        )
        await query.message.reply_text(
            "عکست رو بفرست!",
            reply_markup=DEFAULT_KEYBOARD
        )
        return PHOTO

    if not update.message.photo:
        await update.message.reply_text(
            "متأسفم! 😔 فقط می‌تونم عکس ساده تلگرام رو قبول کنم.\n"
            "از پایین 📎 رو بزن و یه عکس انتخاب کن!",
            reply_markup=DEFAULT_KEYBOARD
        )
        return PHOTO

    context.user_data['photo'] = update.message.photo[-1].file_id
    context.user_data['current_state'] = EDIT

    await update.message.reply_text(
        "عجب عکس باحالی! 😍\nنیاز به ادیت داره؟ ✂️\nیعنی می‌خوای چیزی توش عوض کنی؟\n"
        "فتوشاپ‌کارای ماهرمون رایگان برات انجام می‌دن. 🖌️",
        reply_markup=ReplyKeyboardMarkup([["بله", "خیر"]], one_time_keyboard=True, resize_keyboard=True)
    )
    return EDIT

async def edit(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"Handling edit selection: {update.message.text}")
    context.user_data['edit'] = update.message.text
    if context.user_data['edit'] not in ["بله", "خیر"]:
        await update.message.reply_text(
            "لطفاً فقط 'بله' یا 'خیر' رو بگو! 😊",
            reply_markup=ReplyKeyboardMarkup([["بله", "خیر"]], one_time_keyboard=True, resize_keyboard=True)
        )
        return EDIT

    if context.user_data['edit'] == "خیر":
        await update.message.reply_text("باشه! ✅", reply_markup=DEFAULT_KEYBOARD)
    else:
        await update.message.reply_text("حله! فتوشاپ‌کارامون زودی دست به کار می‌شن! ✂️", reply_markup=DEFAULT_KEYBOARD)

    context.user_data['current_state'] = DISCOUNT

    await update.message.reply_text(
        "کد تخفیف داری؟ 🎁\nهمینجا برامون بنویس، یا دکمه زیر رو بزن:",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("💸 تخفیف ندارم", callback_data="no_discount")]])
    )
    return DISCOUNT

async def discount(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info("Entering discount state...")
    if update.callback_query:
        query = update.callback_query
        await query.answer()
        if query.data == "no_discount":
            context.user_data['discount'] = "ندارد"
            await query.message.reply_text(
                "باشه، بدون کد تخفیف ادامه می‌دیم. 😊\n"
                "لطفاً تأیید کن که می‌خوای بدون کد تخفیف ادامه بدی:",
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("✅ تأیید", callback_data="confirm_discount")]
                ])
            )
            return CONFIRM_DISCOUNT
    else:
        discount_code = update.message.text.lower()
        if discount_code in DISCOUNT_CODES:
            context.user_data['discount'] = discount_code
            await update.message.reply_text("یه لحظه صبر کن بررسی کنم... ⏳", reply_markup=DEFAULT_KEYBOARD)
            await asyncio.sleep(4)
            await update.message.reply_text(
                "درسته! کد تخفیفت اعمال شد ✅\n"
                "لطفاً تأیید کن که می‌خوای با این کد تخفیف ادامه بدی:",
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("✅ تأیید", callback_data="confirm_discount")]
                ])
            )
            return CONFIRM_DISCOUNT
        else:
            await update.message.reply_text(
                "این کد تخفیف درست نیست! ❌\nیه کد ۴ حرفی درست بزن یا 'تخفیف ندارم' رو انتخاب کن!",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("💸 تخفیف ندارم", callback_data="no_discount")]])
            )
            return DISCOUNT

async def confirm_discount(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()

    user_id = context.user_data['user_id']
    context.user_data['order_completed'] = True
    remove_reminders(user_id)

    base_price = SIZES[context.user_data['size']]['price']
    discount_amount = 240000 if context.user_data['discount'] in DISCOUNT_CODES else 0
    extra_discount = 100000 if get_extra_discount_eligible(user_id) else 0
    final_price = base_price - discount_amount - extra_discount
    final_price_str = f"{final_price:,} تومان".replace(',', '،')

    summary = (
        "📋 خلاصه سفارشت:\n\n"
        f"محصول: {context.user_data['product']}\n"
        f"ابعاد: {context.user_data['size']}\n"
        f"ادیت عکس: {context.user_data['edit']}\n"
        f"کد تخفیف: {context.user_data['discount']}\n"
        f"قیمت پایه: {base_price:,} تومان\n"
        f"تخفیف کد: {discount_amount:,} تومان\n"
        f"تخفیف اضافی: {extra_discount:,} تومان\n"
        f"قیمت نهایی: {final_price_str}\n\n"
        "آیا مطمئنی که می‌خوای سفارش رو ثبت کنی؟"
    )
    await query.message.reply_text(
        summary,
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("✅ تأیید سفارش", callback_data="confirm_order")]
        ])
    )
    return DISCOUNT

async def confirm_order(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    user_id = context.user_data['user_id']
    base_price = SIZES[context.user_data['size']]['price']
    discount_amount = 240000 if context.user_data['discount'] in DISCOUNT_CODES else 0
    extra_discount = 100000 if get_extra_discount_eligible(user_id) else 0
    final_price = base_price - discount_amount - extra_discount
    final_price_str = f"{final_price:,} تومان".replace(',', '،')

    if not context.user_data.get('username'):
        context.user_data['current_state'] = CONTACT
        await query.message.reply_text(
            "لطفاً شماره تلفنتون رو به اشتراک بذارید 📞",
            reply_markup=ReplyKeyboardMarkup(
                [[KeyboardButton("ارسال شماره تلفن 📱", request_contact=True)]],
                one_time_keyboard=True,
                resize_keyboard=True
            )
        )
        return CONTACT

    extra_discount_message = " و به‌خاطر تکمیل سریع سفارش، ۱۰۰,۰۰۰ تومن تخفیف بیشتر برات اعمال شد! 🎉" if extra_discount else ""
    await query.message.reply_text(
        f"سفارشت ثبت شد! 🎉\nمنتظر پیاممون باش. زودی باهات تماس می‌گیریم و هماهنگ می‌شیم! 📞\n"
        f"مرسی که با oro همراه شدی! 🙏{extra_discount_message}",
        reply_markup=DEFAULT_KEYBOARD
    )

    await query.message.reply_text(
        "راستی اینم پیج اینستامونه: @oro.stringart\nبه دوستات هم معرفی کن 📷\nhttps://instagram.com/oro.stringart",
        disable_web_page_preview=False
    )

    marketer = f" (بازاریاب: {DISCOUNT_CODES[context.user_data['discount']]})" if context.user_data['discount'] in DISCOUNT_CODES else ""
    extra_discount_operator = " (تخفیف بیشتر ۱۰۰,۰۰۰ تومانی اعمال شد)" if extra_discount else ""
    message_to_operator = (
        "#سفارش\n"
        f"محصول: {context.user_data['product']}\n"
        f"ابعاد: {context.user_data['size']}\n"
        f"آیدی: @{context.user_data['username']}\n"
        f"ادیت عکس: {context.user_data['edit']}\n"
        f"کد تخفیف: {context.user_data['discount']}{marketer}{extra_discount_operator}\n"
        f"قیمت نهایی: {final_price_str}"
    )
    try:
        await context.bot.send_message(chat_id=OPERATOR_ID, text=message_to_operator)
        await context.bot.send_photo(chat_id=OPERATOR_ID, photo=context.user_data['photo'])
    except Exception as e:
        logger.error(f"Error sending to operator: {e}")
        await context.bot.send_message(chat_id=OPERATOR_ID, text=f"خطا در ارسال به اپراتور: {e}")

    context.user_data.clear()
    return ConversationHandler.END

async def contact(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info("Entering contact state...")
    if update.message.contact:
        phone_number = update.message.contact.phone_number
        context.user_data['contact'] = phone_number

        user_id = context.user_data['user_id']
        context.user_data['order_completed'] = True
        remove_reminders(user_id)

        base_price = SIZES[context.user_data['size']]['price']
        discount_amount = 240000 if context.user_data['discount'] in DISCOUNT_CODES else 0
        extra_discount = 100000 if get_extra_discount_eligible(user_id) else 0
        final_price = base_price - discount_amount - extra_discount
        final_price_str = f"{final_price:,} تومان".replace(',', '،')

        extra_discount_message = " و به‌خاطر تکمیل سریع سفارش، ۱۰۰,۰۰۰ تومن تخفیف بیشتر برات اعمال شد! 🎉" if extra_discount else ""
        await update.message.reply_text(
            f"ممنون که شماره‌ت رو به اشتراک گذاشتی! 🙏{extra_discount_message}",
            reply_markup=DEFAULT_KEYBOARD
        )
        await update.message.reply_text(
            f"سفارشت ثبت شد! 🎉\nمنتظر پیاممون باش. زودی باهات تماس می‌گیریم و هماهنگ می‌شیم! 📞\n"
            f"مرسی که با oro همراه شدی! 🙏",
            reply_markup=DEFAULT_KEYBOARD
        )

        await update.message.reply_text(
            "راستی اینم پیج اینستامونه: @oro.stringart\nبه دوستات هم معرفی کن 📷\nhttps://instagram.com/oro.stringart",
            disable_web_page_preview=False
        )

        marketer = f" (بازاریاب: {DISCOUNT_CODES[context.user_data['discount']]})" if context.user_data['discount'] in DISCOUNT_CODES else ""
        extra_discount_operator = " (تخفیف بیشتر ۱۰۰,۰۰۰ تومانی اعمال شد)" if extra_discount else ""
        message_to_operator = (
            "#سفارش\n"
            f"محصول: {context.user_data['product']}\n"
            f"ابعاد: {context.user_data['size']}\n"
            f"شماره تماس: {context.user_data['contact']}\n"
            f"ادیت عکس: {context.user_data['edit']}\n"
            f"کد تخفیف: {context.user_data['discount']}{marketer}{extra_discount_operator}\n"
            f"قیمت نهایی: {final_price_str}"
        )
        try:
            await context.bot.send_message(chat_id=OPERATOR_ID, text=message_to_operator)
            await context.bot.send_photo(chat_id=OPERATOR_ID, photo=context.user_data['photo'])
        except Exception as e:
            logger.error(f"Error sending to operator: {e}")
            await context.bot.send_message(chat_id=OPERATOR_ID, text=f"خطا در ارسال به اپراتور: {e}")

        context.user_data.clear()
        return ConversationHandler.END
    else:
        await update.message.reply_text(
            "لطفاً فقط دکمه 'ارسال شماره تلفن 📱' رو بزن تا شماره‌ت رو به اشتراک بذاری! 😊",
            reply_markup=ReplyKeyboardMarkup(
                [[KeyboardButton("ارسال شماره تلفن 📱", request_contact=True)]],
                one_time_keyboard=True,
                resize_keyboard=True
            )
        )
        return CONTACT

async def restart(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"User {update.effective_user.id} restarted the order process")
    user_id = context.user_data.get('user_id')
    if user_id:
        remove_reminders(user_id)
    context.user_data.clear()
    await update.message.reply_text("بیا دوباره شروع کنیم! 😊")
    await update.message.reply_text(
        "برای دیدن نمونه‌کارامون، پیج اینستامون رو حتماً ببین:\n👇 یک محصول انتخاب کن",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("محصولات 🎉", switch_inline_query_current_chat="محصولات")],
            [
                InlineKeyboardButton("❓ سوالات پرتکرار", switch_inline_query_current_chat="سوالات"),
                InlineKeyboardButton("💬 تماس با پشتیبانی", callback_data="support")
            ],
            [
                InlineKeyboardButton("📖 درباره ما", callback_data="about_us"),
                InlineKeyboardButton("📷 اینستاگرام", url="https://instagram.com/oro.stringart")
            ]
        ])
    )
    return PRODUCT

async def support(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"User {update.effective_user.id} requested support")
    if update.callback_query:
        await update.callback_query.answer()
        await update.callback_query.message.reply_text(
            "به پشتیبانی خوش اومدی! 😊\n"
            "اگه سؤالی داری یا به مشکلی خوردی، همینجا برامون بنویس.\n"
            "یا اگه می‌خوای با اپراتور صحبت کنی، دکمه زیر رو بزن:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("📞 ارسال تیکت", callback_data="send_to_message")]
            ])
        )
    else:
        await update.message.reply_text(
            "به پشتیبانی خوش اومدی! 😊\n"
            "اگه سؤالی داری یا به مشکلی خوردی، همینجا برامون بنویس.\n"
            "یا اگه می‌خوای با اپراتور صحبت کنی، دکمه زیر رو بزن:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("📞 ارسال تیکت", callback_data="send_to_message")]
            ])
        )
    return SUPPORT

async def handle_support(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"Handling support message from user: {update.effective_user.id}")
    if update.callback_query:
        query = update.callback_query
        await query.answer()
        if query.data == "send_to_message":
            await query.message.reply_text(
                "لطفاً سؤال یا مشکلی که داری رو بنویس تا به اپراتور بفرستم:",
                reply_markup=DEFAULT_KEYBOARD
            )
            context.user_data['awaiting_support_message'] = True
            return SUPPORT
    else:
        if context.user_data.get('awaiting_support_message'):
            user_message = update.message.text
            user_identifier = f"@{context.user_data['username']}" if context.user_data.get('username') else context.user_data.get('contact', 'نامشخص')
            await update.message.reply_text(
                f"پیامت:\n{user_message}\n\nبرای ارسال به اپراتور تأیید کن:",
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("📤 ارسال تیکت", callback_data="send_to_operator")]
                ])
            )
            context.user_data['support_message'] = user_message
            context.user_data['awaiting_support_message'] = False
            return SUPPORT
        else:
            await update.message.reply_text(
                "لطفاً اول دکمه‌ی 'ارسال تیکت' رو بزن تا بتونم پیامت رو ثبت کنم! 😊",
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("📞 ارسال تیکت", callback_data="send_to_message")]
                ])
            )
            return SUPPORT

async def send_to_operator(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    user_message = context.user_data.get('support_message', '')
    user_identifier = f"@{context.user_data.get('username', '')}" if context.user_data.get('username') else context.user_data.get('contact', 'نامشخص')
    try:
        await context.bot.send_message(
            chat_id=OPERATOR_ID,
            text=f'#تیکت\nکاربر: {user_identifier}\nمتن: {user_message}'
        )
        await query.message.reply_text(
            "پیامت برای اپراتور ارسال شد! 📤 زودی باهات تماس می‌گیرن.",
            reply_reply=DEFAULT_KEYBOARD
        )
    except Exception as e:
        logger.error(f"Error sending to operator: {e}")
        await query.message.reply_text(
            "متأسفم، خطایی پیش اومد. لطفاً دوباره امتحان کن! 😔",
            reply_markup=DEFAULT_KEYBOARD
        )
    context.user_data.pop('support_message', None)
    context.user_data.pop('awaiting_support_message', None)
    return ConversationHandler.END

async def handle_faq_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    logger.info(f"Handling FAQ selection: {update.message.text}")
    message_text = update.message.text
    if message_text in FAQ:
        await update.message.reply_text(FAQ[message_text]['answer'], reply_markup=DEFAULT_KEYBOARD)
    else:
        await update.message.reply_text(
            "لطفاً یه سؤال از منو انتخاب کن! 😊\nبا تایپ '@BotUsername سوالات' سوالات رو ببین.",
            reply_markup=DEFAULT_KEYBOARD
        )
    return FAQ_STATE

async def about_us(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    logger.info(f"User {update.effective_user.id} requested about us")
    await update.callback_query.answer()
    await update.callback_query.message.reply_text(
        "ما یه تیم جوون و پرانرژی از تهران هستیم که عاشق هنر و خلاقیتیم! 🎨\n"
        "با تابلوهای نخی دست‌سامون، خاطراتت رو به یه اثر هنری تبدیل می‌کنیم. 🖼️\n"
        "هر تابلو با عشق و ظرافت ساخته می‌شه تا تو و عزیزانت رو خوشحال کنه! ❤️",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("📷 اینستاگرام", url="https://instagram.com/oro.stringart")]
        ])
    )

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    logger.error(f"Error occurred: {context.error}")
    if isinstance(context.error, telegram.error.Conflict):
        logger.error("Conflict error: Another instance of the bot is running. Stopping this instance...")
        await context.application.stop()
    else:
        logger.error(f"Unhandled error: {context.error}")
        with open("error_log.txt", "a") as f:
            f.write(f"{datetime.now()} - {context.error}\n")

def main():
    logger.info("Building Telegram application...")
    application = Application.builder().token(BOT_TOKEN).build()

    application.bot.delete_webhook(drop_pending_updates=True)
    logger.info("Webhook disabled")

    init_db()

    reminder_thread = threading.Thread(target=reminder_loop, args=(application,), daemon=True)
    reminder_thread.start()
    logger.info("Reminder thread started")

    conv_handler = ConversationHandler(
        entry_points=[
            CommandHandler('start', start),
            MessageHandler(filters.Regex('^شروع مجدد 🎉$'), restart),
            MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
            CallbackQueryHandler(support, pattern="^support$"),
            CallbackQueryHandler(about_us, pattern="^about_us$"),
            CallbackQueryHandler(resume_order, pattern="^resume_order$"),
            CallbackQueryHandler(restart, pattern="^restart$"),
        ],
        states={
            PRODUCT: [
                MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
                CallbackQueryHandler(support, pattern="^support$"),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
                MessageHandler(filters.Text() & ~filters.Command(), handle_product_selection)
            ],
            SIZE: [
                MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
                CallbackQueryHandler(support, pattern="^support$"),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
                MessageHandler(filters.Text() & ~filters.Command(), handle_size_selection)
            ],
            PHOTO: [
                MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
                CallbackQueryHandler(support, pattern="^support$"),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
                CallbackQueryHandler(photo, pattern="^understood$"),
                MessageHandler(filters.ALL & ~filters.Command(), photo)
            ],
            EDIT: [
                MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
                CallbackQueryHandler(support, pattern="^support$"),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
                MessageHandler(filters.Regex('^(بله|خیر)$'), edit)
            ],
            DISCOUNT: [
                MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
                CallbackQueryHandler(support, pattern="^support$"),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
                CallbackQueryHandler(discount, pattern="^no_discount$"),
                CallbackQueryHandler(confirm_order, pattern="^confirm_order$"),
                MessageHandler(filters.Text() & ~filters.Command(), discount)
            ],
            CONFIRM_DISCOUNT: [
                CallbackQueryHandler(confirm_discount, pattern="^confirm_discount$")
            ],
            CONTACT: [
                MessageHandler(filters.CONTACT, contact),
                MessageHandler(filters.ALL & ~filters.Command(), contact),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
            ],
            SUPPORT: [
                CallbackQueryHandler(handle_support, pattern="^send_to_message$"),
                CallbackQueryHandler(send_to_operator, pattern="^send_to_operator$"),
                MessageHandler(filters.Text() & ~filters.Command(), handle_support),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
            ],
            FAQ_STATE: [
                MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
                MessageHandler(filters.Text() & ~filters.Command(), handle_faq_selection),
                CallbackQueryHandler(about_us, pattern="^about_us$"),
            ],
        },
        fallbacks=[
            CommandHandler('start', start),
            MessageHandler(filters.Regex('^شروع مجدد 🎉$'), restart),
            MessageHandler(filters.Regex('^تماس با پشتیبانی 💬$'), support),
            CallbackQueryHandler(restart, pattern="^restart$"),
        ],
        per_chat=True,
        per_user=True,
        per_message=False
    )
    logger.info("Adding handlers to application...")
    application.add_handler(conv_handler)
    application.add_handler(InlineQueryHandler(inlinequery))
    application.add_error_handler(error_handler)

    logger.info("Bot is running...")
    try:
        application.run_polling()
    finally:
        global running
        running = False
    logger.info("Polling started successfully!")

if __name__ == '__main__':
    main()
