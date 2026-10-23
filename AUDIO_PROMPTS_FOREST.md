# ElevenLabs: звуки лесного поста

Согласованный набор для следующего наполнения леса. Пока это рецепты для генерации,
не подключённые записи. Стартовые значения, окончательный отбор — на слух владельца.
WAV; Automatically improve short or unclear prompts — **Off во всех строках**.
Influence — следование тексту, не громкость. Первые семь строк важнее остальных.
Один шаг — один контакт ноги, не запись ходьбы. Повторами управляет игра.

| Назначение / имя | Промпт | Duration | Loop | Influence | Вариантов |
| --- | --- | --- | --- | --- | --- |
| Фон `forest_ambience` | A seamless stereo ambience of a quiet conifer forest on an overcast late afternoon. Broad, soft movement of air through distant treetops, with subtle natural variation and a sense of open space. Present and textured, calm but slightly lonely. No close animal calls, footsteps, music or dramatic gusts. | 30 с вручную | On | 40% | 1–2 |
| Грунт `footstep_dirt` | One isolated walking footstep in a worn outdoor boot on a compacted forest dirt path. A solid, rounded sole contact with a little loose grit and a short earthy scuff. Natural outdoor foley, clearly recorded at close range. A single step, not a walking sequence. | 1 с вручную | Off | 65% | 3–4 |
| Трава `footstep_grass` | One isolated walking footstep in an outdoor boot on short forest grass over firm soil. Soft leafy compression over a grounded footfall, with a brief gentle rustle. Natural close outdoor foley. A single step, not a walking sequence. | 1 с вручную | Off | 65% | 3–4 |
| Влажная земля `footstep_wet_dirt` | One isolated boot footstep on damp forest soil. A firm, soft impact with a small sticky release and a little wet grit. Moist earth rather than deep sludge, restrained and believable. Natural close outdoor foley. A single step. | 1 с вручную | Off | 65% | 3–4 |
| Мелкая лужа `footstep_puddle` | One isolated boot footstep into a shallow puddle on a dirt path. A grounded sole impact, a small clear splash and a brief scattering of water droplets. Natural close outdoor foley, modest water depth. A single step, not a sequence. | 1,2 с вручную | Off | 65% | 3–4 |
| Касание травы `grass_brush` | One brief swish of long grass brushing against trouser legs as a person passes through. Soft flexible blades bending and slipping past fabric, light and textured. Close natural foley, with a clean beginning and natural finish. | 1,2 с вручную | Off | 55% | 2–3 |
| Касание куста `bush_brush` | One brief pass through a leafy woodland shrub. Several leaves and thin flexible twigs brush across a jacket, producing a layered, soft rustle with a little woody detail. Natural close foley, believable and gentle rather than a loud branch snap. | 1,5 с вручную | Off | 55% | 2–3 |
| Порыв `forest_wind_gust` | One gentle breeze moving through the crowns of conifer trees. It slowly swells, shifts unevenly through the branches and settles again, with a soft rounded body and fine foliage movement. Natural outdoor recording, without a sharp whistle or dramatic storm sound. | 10 с вручную | Off | 40% | 2–3 |
| Ворона `forest_crow` | A distant crow gives a short, natural call from the edge of a conifer forest. Slightly softened by distance, with open outdoor space around the voice. An ordinary woodland bird, neither a horror scream nor an exaggerated theatrical call. | Auto | Off | 45% | 2 |
| Дятел `forest_woodpecker` | A distant woodpecker makes one short, uneven burst of quick tapping on a tree trunk in a quiet forest, then stops. Small, dry wooden taps softened by distance, with natural outdoor space. An isolated bird activity, not a continuous rhythmic loop. | Auto | Off | 50% | 1–2 |
| Ствол (необязательно) `forest_tree_creak` | A large outdoor tree trunk makes one low, subtle wooden groan as a light breeze puts tension on it, then settles. Deep fibrous wood movement, natural and restrained, heard from several meters away. No high squeak or indoor furniture creak. | 4 с вручную | Off | 50% | 1–2 |

Сохранять удачные варианты как имя.wav, имя-2.wav, имя-3.wav. Не нужно сохранять
все предложенные сервисом варианты. Скрип, похожий на стул, отвергнуть; его можно
вообще не использовать. Животных/узнаваемые порывы не вшивать в постоянную петлю.
Автоулучшение выключено для воспроизводимости первого сравнения, не из-за общего
запрета на этот режим. Для одиночных шагов важна форма события, не точность длины
контейнера WAV; избыточную тишину можно подрезать при подготовке банка.

Документация сервиса: https://elevenlabs.io/docs/eleven-creative/playground/sound-effects
