# Единый стиль промптов для 2.5D-ассетов («Лунный мицелий»)

Владелец 03.11.2026: «слишком реалистично не надо, как в ChatGPT». Любой генератор (ChatGPT, Arena `gpt-image-2.5`) получает этот префикс **первым**:

> Stylized hand-painted 3D-render look of a polished premium mobile game: soft rounded shapes, simplified readable forms, clean edges, smooth painterly gradients, slightly saturated glowing colours, cute and magical. NOT photorealistic, NOT a photograph, no harsh noise, no film grain, no fine realistic clutter. Tilted view about 50 degrees from above, soft light from the top-left, moonlit blue-violet night palette with cyan and violet glow.

Дальше — описание предмета. Для спрайтов: «on a flat pure magenta #FF00FF background, wide empty space between items, no ground shadow, no text». Для земли: «portrait 9:19.5, edge to edge, no props, no characters, no text, calm open centre, denser details at the left and right edges».

Резкость на телефоне: земля — композиционная плита + бесшовный тайл деталей в шейдере (`shaders/ground_detail.gdshader`, `tools/make_detail_tile.py`); спрайты — со включёнными mipmaps, соотношение «пикселей экрана на пиксель текстуры» не выше ~1.
