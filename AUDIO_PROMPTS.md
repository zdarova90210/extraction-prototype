# Единый справочник промптов ElevenLabs

Актуальные промпты и настройки собраны в этом файле: 9 строк окружения/рейда,
26 текущих игровых звуков и 4 профиля контейнеров в запас.

## 1. Окружение и события рейда

Выбранный владельцем фон склада #3 уже подключён для теста.
Владелец прошёл весь справочник, кроме четырёх будущих контейнеров, отобрал
104 файла и предоставил внешнюю папку для анализа. Все 35 назначений покрыты;
первая группа (оружие/бой/шаги: 32 записи) уже подготовлена и подключена для теста,
остальные записи ещё не подключены. Он менял некоторые
промпты/настройки: строки ниже — рецепты, а не подтверждённые настройки экспорта.
Итоги и приоритеты — AUDIO_BANK_REVIEW.md. Новые выбранные файлы не считать
отклонёнными только из-за раннего отказа от предыдущей генерации пяти звуков.
Новые промпты для остальных текущих событий находятся ниже, в разделе 2.
Лампа в запас до появления её объекта; события рейда —
кандидаты следующей отдельной поставки. Скачивать WAV. Для одиночных событий допустим Auto; длительности — ориентиры.
Для этой таблицы Looping указан в каждой строке; в разделе 2 все звуки без зацикливания.
Influence — следование описанию, не громкость. Все цифры стартовые, нужен отбор на слух.

| Звук / имя файла | Промпт | Duration | Looping | Influence |
| --- | --- | --- | --- | --- |
| Порыв ветра `wind_gust` | A gentle outdoor breeze slowly rises, moves past an open warehouse doorway and naturally subsides. Soft rounded airflow with irregular movement, realistic and restrained. No whistling, breathing, static hiss, leaves, voices or music. One isolated gust. | 12 с | Off | 35% |
| Дребезг металла `metal_rattle` | One brief light rattle of a loose corrugated steel panel moved by a breeze. Muted metallic vibration with a short natural decay, heard from several meters away outdoors. No squeaky hinges, chair creaks, heavy impacts, footsteps, voices or music. | 3 с | Off | 60% |
| Фон лампы `lamp_buzz` | An old industrial light fixture running with a low electrical murmur and faint, irregular crackling. Soft, slightly worn and alive, with natural small variations. Seamless environmental loop recorded from a few meters away. | 10 с | On | 35% |
| Сбой лампы `lamp_sputter` | An aging industrial light briefly flickers and recovers, with an irregular flutter of electrical crackle and a soft resonant buzz. A small, believable disturbance heard from a few meters away. | Auto | Off | 40% |
| Начало рейда `raid_start` | A brief instrumental cue for entering an abandoned industrial site. A low, warm musical motif with subtle tension and a sense of anticipation, ending with a gentle lingering resonance. Grounded cinematic sound design. | Auto | Off | 40% |
| Импульс эвакуации `extraction_pulse` | One warm musical pulse in a comfortable low-mid register, with a rounded body, soft attack and a short gentle decay. Subtle, tactile and reassuring, designed to remain pleasant when repeated. | 1 с | Off | 40% |
| Отмена эвакуации `extraction_cancel` | A short, gentle musical cue for an interrupted action. A small downward musical gesture that settles quietly, feeling neutral and slightly unfinished. Soft, understated game sound design. | Auto | Off | 40% |
| Успешный рейд `raid_success` | A four-second instrumental musical stinger for successful extraction in a gritty industrial survival game. Three restrained ascending felt-piano notes over a warm low string chord, resolving with quiet relief. Serious, grounded and slightly dark, never cheerful or triumphant. Clear opening and natural reverb tail. Instrumental only, no vocals, speech, percussion or sound effects. | 4 с | Off | 60% |
| Провал рейда `raid_failure` | A four-second instrumental musical stinger for a failed extraction in a gritty industrial survival game. Two sparse descending felt-piano notes over dark low strings, ending on a soft unresolved chord. Somber and restrained, conveying loss without melodrama. Clear opening and natural reverb tail. Instrumental only, no vocals, speech, percussion or sound effects. | 4 с | Off | 60% |

Сначала один запуск на строку, сохранить удачные варианты. Ветру и металлу
полезны 2–3 разные записи. Точное усиление делать после выбора файла;
не генерировать весь атмосферный микс одной дорожкой.

Успех/провал переработаны по обратной связи владельца: описание рации давало
непонятную речь. Для результата разрешены короткие серьёзные инструментальные
мотивы; запрета мелодии нет. Оба — одна палитра приглушённого фортепиано/низких
струнных, разное завершение. Это направление для теста, не утверждённые ассеты.
Если 4 с обрезают естественный хвост, попробовать 5 с; при повторной речи отвергнуть
вариант. Постоянная музыка на уровне этим решением не добавляется.

Пять промптов повторно упрощены по обратной связи владельца. Рейд/импульс/
отмена описываются через характер музыкального акцента без рации и обязательного
инструмента; лампа — через приглушённую электрическую фактуру без сложной
постановки действий. Influence 35–40% — старт для более свободных вариантов,
не гарантия качества. Отрицательные перечни исключений убраны из этих строк.
Сохранять новые файлы с суффиксом _v2, чтобы отличать от отклонённых вариантов.

Эвакуация получает одиночный импульс, повторением управляет таймер в игре.
Для теста предлагается наращивать главным образом частоту повторов, избегая
всё более высокого писка и громкости. Готовое пятисекундное нарастание не нужно.
Смерть и провал — согласованный
эпизод без двух конкурирующих сигналов. Специальный сигнал убийства врага не нужен.
Окружение привязывать к понятным объектам; листву и скрип стула не возвращать.
Не вшивать узнаваемые порывы в основную петлю: владелец замечает повтор.
Для новых деталей ориентир — примерно половина прежней амплитуды замене скрипа,
около 70% остальным. Уровни предварительные, проверять по новой записи в игре.

[Настройки ElevenLabs](https://elevenlabs.io/docs/eleven-creative/playground/sound-effects).

## 2. Текущие игровые звуки и дополнительные контейнеры

Первый набор из раздела 1 владелец уже сгенерировал и хранит вне проекта;
обновлённые кандидаты уже предоставлены. Эта таблица хранит рецепты текущих звуков.
Сначала сравнить кандидатов с существующими, затем выбирать записи для замены.
Оружие/бой/шаги заменены новым банком и ждут теста; взаимодействия/лечение
ещё не заменялись. Игровые события остаются прежними.

Для всех строк: **Looping Off, скачивание WAV**. Duration Auto позволяет модели
выбрать естественную длину одиночного события; где указаны 2 с, это короткий
фрагмент повторяемого действия. Influence — стартовый ориентир, не показатель
качества. Если теряется нужный материал/действие, сначала уточнить описание.
Громкость, пространственность, монтаж и обрезка пауз настраиваются после отбора.

Один файл — один выстрел, одно попадание, один шаг или одно законченное действие.
Поиск/лечение — фрагменты процесса, их повторяет игровой код до окончания/отмены.
Перезарядка уже имеет отдельные начало и конец: генерировать их отдельно.
Для частых выстрелов, попаданий и шагов сохранить 3–5 разных удачных вариантов;
для остальных сначала 1–2. Не заказывать серию разных событий внутри одного файла.

### Оружие и бой — события уже есть

| Звук / имя файла | Промпт | Duration | Influence |
| --- | --- | --- | --- |
| Карабин: выстрел `carbine_shot` | One punchy shot from a compact modern carbine, with a crisp attack, a tight low-end thump and a brief natural outdoor tail. Realistic isolated weapon recording. | Auto | 50% |
| Охранник: выстрел `rifle_shot` | One powerful assault-rifle shot with a weighty report, a rough mechanical edge and a natural outdoor decay. Full-bodied and distinct, like an isolated field recording. | Auto | 50% |
| Охранник: изготовка `guard_ready` | Close foley of a guard bringing a rifle firmly to the shoulder and settling their grip. A brief blend of clothing movement, sling tension and small weapon-handling sounds. No gunshot or speech. | Auto | 45% |
| Пустой спуск `dry_trigger` | One dry trigger pull on an unloaded modern rifle: a tactile mechanical click with a small metallic body. Clean close foley. | Auto | 55% |
| Карабин: начало перезарядки `carbine_reload_start` | Close foley of changing a carbine magazine: the release clicks, the empty magazine slides out and a fresh magazine seats firmly. Tactile metal and polymer handling. | Auto | 50% |
| Карабин: конец перезарядки `carbine_reload_finish` | One compact carbine bolt-release action. A spring-driven metallic snap followed by a small solid settling clack. Realistic close weapon foley. | Auto | 50% |
| Охранник: начало перезарядки `rifle_reload_start` | An assault-rifle magazine change, with a worn metal magazine rocking out and a replacement locking into place. Solid, slightly rough mechanical foley. | Auto | 50% |
| Охранник: конец перезарядки `rifle_reload_finish` | An assault rifle charging handle pulled back and released once, with a firm metallic slide and a spring-driven return. Close detailed weapon foley. | Auto | 50% |
| Успешный тайминг R `reload_timing` | A small precision gun mechanism clicks smoothly into place with a tight, satisfying metallic snap. Short, tactile and subtly rewarding, suitable for a perfectly timed reload. | Auto | 45% |
| Пуля: бетон/камень `impact_concrete` | One bullet strikes rough concrete, producing a sharp compact impact and a brief scatter of gritty chips and dust. A realistic isolated impact recording. | Auto | 50% |
| Пуля: металл `impact_metal` | One bullet hits thick industrial steel, with a hard metallic strike and a short resonant ring. Solid and weighty, with a natural brief decay. | Auto | 50% |
| Пуля: дерево `impact_wood` | One bullet strikes a solid wooden crate, making a dry cracking thud with a brief spray of small splinters. Close realistic impact foley. | Auto | 50% |
| Попадание во врага `actor_hit` | A compact physical impact against heavy clothing and protective gear, with a dull body thump and a brief fabric movement. Grounded close foley, without a vocal performance. | Auto | 45% |
| Урон игроку `player_damage` | A short close impact against the torso beneath rugged clothing, with a weighty muted thump and a small gear jolt. Immediate and physical, without a vocal performance. | Auto | 45% |

Для одного выстрела охранника не нужна готовая очередь: очередями управляет игра.
Изготовка — движение снаряжения, не передёргивание затвора перед каждой атакой.
Попадания не должны содержать звук исходного выстрела: он уже играет отдельно.
Для пустого спуска и награды R пока достаточно одного общего профиля оружия.
Гибель использует физическую реакцию; отдельной награды за убийство не добавлять.

### Контейнер, инвентарь и лечение — события уже есть

| Звук / имя файла | Промпт | Duration | Influence |
| --- | --- | --- | --- |
| Деревянный ящик: открыть `container_wood_open` | A sturdy wooden storage crate is opened by hand: a simple latch releases and the lid lifts with natural wood friction and a little hardware movement. Detailed practical foley. | Auto | 45% |
| Деревянный ящик: закрыть `container_wood_close` | A wooden storage-crate lid is lowered into place with a solid wooden knock and a small latch settling shut. Natural close foley with a short decay. | Auto | 45% |
| Поиск внутри `loot_search` | Close foley of hands rummaging through loose supplies inside a storage box, with small object movements, wrapping and soft contact against the box. An irregular fragment of searching. | 2 с | 35% |
| Раскрытие предмета `loot_reveal` | A small useful object is uncovered among supplies and set down with a soft tactile tap and a little wrapping movement. A brief satisfying discovery accent. | Auto | 40% |
| Переложить предмет `item_move` | A small piece of scavenged equipment is placed into a canvas backpack, with a soft object tap and a brief fabric movement. Compact, tactile inventory foley. | Auto | 40% |
| Выбросить на пол `item_drop` | A small rugged object is dropped a short distance onto a concrete floor, making a compact dull clatter and one small settling movement. Natural isolated foley. | Auto | 45% |
| Поднять с пола `item_pickup` | Close foley of picking up a small object from a concrete floor, with a light scrape, a hand grip and a little equipment movement. Brief and tactile. | Auto | 40% |
| Лечение: начало `heal_start` | A compact first-aid packet is opened by hand, with a crisp medical-wrapper tear and soft gauze unfolding. Clean, detailed close foley. | Auto | 45% |
| Лечение: процесс `heal_process` | Close foley of gently wrapping and adjusting a gauze bandage, with soft cloth tension and small hand movements. A short natural fragment of careful first aid. | 2 с | 35% |
| Лечение: завершение `heal_finish` | The end of a bandage is secured with a small strip of medical tape, followed by a gentle final press and a soft cloth movement. A compact finishing action. | Auto | 45% |

Перенос озвучивается после успешной операции; для захвата/начала drag отдельный
файл не нужен. Подбор/выбрасывание уже имеют свои события. Сейчас общий профиль
вещи достаточен; отдельные оружие/жесть/жидкости остаются следующим расширением.
Обычное раскрытие — физический приятный акцент. Особая мелодия редкой находки
остаётся будущей задачей после появления редкостей.

### Шаги — события уже есть, можно сравнить позже

| Звук / имя файла | Промпт | Duration | Influence |
| --- | --- | --- | --- |
| Один шаг: бетон `step_concrete` | One walking step in a practical outdoor boot on dusty concrete, with a grounded heel-to-sole contact and a little grit underfoot. Natural close foley. | Auto | 45% |
| Один шаг: металл `step_metal` | One walking step in a practical outdoor boot on an industrial steel walkway, with a solid sole contact and a short natural panel resonance. Grounded close foley. | Auto | 45% |

Шаги игрока и охранника используют общую семью материала. Не требуется отдельная
генерация для каждого актёра. Отдельный шаг удобнее готовой дорожки ходьбы:
ритм в игре уже следует фактическому движению, включая остановку и смену пола.

### Другие контейнеры — запас, текущие объекты ещё не используют эти профили

| Звук / имя файла | Промпт | Duration | Influence |
| --- | --- | --- | --- |
| Металлический ящик: открыть `container_metal_open` | An industrial metal storage box is opened: its latch releases and the lid lifts with a subdued hinge movement and a little hollow steel resonance. Tactile realistic foley. | Auto | 45% |
| Металлический ящик: закрыть `container_metal_close` | An industrial metal storage-box lid closes with a restrained hollow clunk, followed by its latch clicking into place. Detailed practical foley. | Auto | 45% |
| Сумка: открыть `container_bag_open` | A rugged canvas duffel bag is unzipped and opened by hand. A textured zipper pull followed by soft fabric folding and movement. Close natural foley. | Auto | 45% |
| Сумка: закрыть `container_bag_close` | A rugged canvas duffel bag is gathered closed and zipped shut, with soft fabric handling and a satisfying zipper finish. Close natural foley. | Auto | 45% |

Короткие промпты оставляют свободу фактуре. Если модель добавляет музыку/голоса
или посторонние действия, уточнить только этот сбой, не обрастать общим списком
запретов. Для самого эффекта нужны разборчивая атака и естественный хвост;
окружение/дальность добавляются отдельно при подключении к игре.

[Рекомендации ElevenLabs](https://elevenlabs.io/docs/help-center/product/core-capabilities/sound-effects/how-do-i-prompt-for-sound-effects).
