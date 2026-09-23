package com.vibekits.whacdemo;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import java.util.Random;

/**
 * 原生 Android 打地鼠 —— 1920x1280 横屏 PAD 专用，单文件、无 AndroidX。
 *
 * 规则：3x3 九宫格地鼠随机冒头；60 秒倒计时；得分/最高分持久化；开始/重玩；
 * 每次点按出一次锤击；命中地鼠头部时在头部出现局部裂纹，随后逐渐收拢淡出恢复。
 *
 * 布局（避免遮挡）：横屏 = 左侧信息栏（得分/倒计时/命中漏掉/最高分/按钮）+ 右侧正方形九宫格；
 * 竖屏 = 顶部三卡信息条 + 板面 + 底部按钮。所有地鼠、锤子、裂纹、飘字都裁剪在板面/单元格内，
 * 开始与结束提示卡只画在板面内部，按钮与计分始终可见可点。
 *
 * 包名保持 com.vibekits.whacdemo；由 am start --display 2 决定显示到哪块屏，代码内不指定 display。
 */
public class WhacActivity extends Activity {

    private GameView gameView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        Window window = getWindow();
        window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        gameView = new GameView(this);
        setContentView(gameView);
        applyImmersive();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            applyImmersive();
        }
    }

    /** 隐藏系统栏，保证第二屏上九宫格、按钮与计分不被系统 UI 压住。 */
    private void applyImmersive() {
        if (gameView == null) {
            return;
        }
        gameView.setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (gameView != null) {
            gameView.onShown();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (gameView != null) {
            gameView.onHidden();
        }
    }
}

/** 自绘游戏视图：布局、计时、命中判定与全部绘制都在这里完成。 */
class GameView extends View {

    private enum State { READY, RUNNING, OVER }

    // ---- 规则
    private static final int COLS = 3;
    private static final int ROWS = 3;
    private static final int HOLES = COLS * ROWS;
    private static final long GAME_MS = 60000L;
    private static final long POP_MS = 150L;
    private static final long LIFE_MIN_MS = 560L;
    private static final long LIFE_MAX_MS = 1060L;
    private static final long GAP_MIN_MS = 240L;
    private static final long GAP_MAX_MS = 620L;
    private static final long FIRST_MOLE_MS = 520L;
    private static final long RESTART_GUARD_MS = 700L;
    private static final int HIT_SCORE = 10;
    private static final float HIT_MIN_POP = 0.30f;

    // ---- 动效
    private static final long FLASH_MS = 280L;
    private static final long HAMMER_MS = 420L;
    private static final long STRUCK_MS = 620L;
    private static final long CRACK_MS = 1500L;
    private static final long SCORE_POP_MS = 780L;
    private static final long DUST_MS = 340L;
    private static final long URGENT_MS = 10000L;

    // ---- 统一配色
    private static final int BG_A = 0xFF0C2416;
    private static final int BG_B = 0xFF06120A;
    private static final int PANEL_FILL = 0xFF122C1C;
    private static final int PANEL_EDGE = 0xFF2B5C3C;
    private static final int CARD_FILL = 0xFF173422;
    private static final int CARD_EDGE = 0xFF2E6140;
    private static final int TEXT_MAIN = 0xFFF3FBF4;
    private static final int TEXT_LABEL = 0xFF8FC79E;
    private static final int TEXT_DIM = 0xFF74A382;
    private static final int ACCENT = 0xFFFFC13B;
    private static final int ACCENT_EDGE = 0xFF8A6212;
    private static final int ACCENT_TEXT = 0xFF2A1B06;
    private static final int BTN_OFF_FILL = 0xFF26402E;
    private static final int BTN_OFF_EDGE = 0xFF35563E;
    private static final int BTN_OFF_TEXT = 0xFF7FA98B;
    private static final int BOARD_FILL = 0xFF0A2013;
    private static final int BOARD_EDGE = 0xFF2A5B3A;
    private static final int TILE_FILL = 0xFF153A22;
    private static final int TILE_EDGE = 0xFF24512F;
    private static final int GRASS = 0xFF377D42;
    private static final int GRASS_RIM = 0xFF2E6238;
    private static final int HOLE_DARK = 0xFF081A10;
    private static final int HOLE_LIP = 0xFF0B2314;
    private static final int DANGER = 0xFFFF6B6B;
    private static final int HIT_GREEN = 0xFF7BE39B;
    private static final int MISS_PINK = 0xFFE3A0A0;
    private static final int MOLE_FUR = 0xFFA98A6E;
    private static final int MOLE_FUR_HI = 0xFFC6AC92;
    private static final int MOLE_SNOUT = 0xFFEADDCB;
    private static final int MOLE_EAR = 0xFF7C5A44;
    private static final int MOLE_EDGE = 0xFF6B4C36;
    private static final int MOLE_PINK = 0xFFF2A79B;

    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();

    private final RectF panel = new RectF();
    private final RectF boardRect = new RectF();
    private final RectF button = new RectF();
    private final RectF[] cells = new RectF[HOLES];
    private final RectF[] holeOvals = new RectF[HOLES];
    private final RectF tmp = new RectF();

    private float viewW = 0f;
    private float viewH = 0f;
    private float margin = 24f;
    private float gap = 20f;
    private boolean landscape = true;
    private Shader bgShader = null;
    private Shader glowShader = null;

    private final Random random = new Random();
    private final SharedPreferences prefs;

    private State state = State.READY;
    private int score = 0;
    private int best = 0;
    private int hits = 0;
    private int misses = 0;
    private int streak = 0;
    private int bestStreak = 0;
    private boolean newRecord = false;

    private int moleIndex = -1;
    private int lastMoleIndex = -1;
    private long moleRiseAt = 0L;
    private long moleSinkAt = 0L;
    private long nextMoleAt = 0L;
    private float pop = 0f;

    private long timeLeftMs = GAME_MS;
    private long lastFrameAt = 0L;
    private long overAt = 0L;

    private int flashIndex = -1;
    private long flashAt = 0L;

    private int struckCell = -1;
    private long struckAt = 0L;
    private float struckPop = 0f;
    private float crackX = 0f;
    private float crackY = 0f;
    private float crackR = 0f;

    private long hammerAt = 0L;
    private float hammerX = 0f;
    private float hammerY = 0f;
    private float hammerR = 0f;
    private boolean hammerHit = false;

    private long dustAt = 0L;
    private float dustX = 0f;
    private float dustY = 0f;
    private int dustCell = -1;

    private int popScore = 0;
    private float popScoreX = 0f;
    private float popScoreY = 0f;
    private long popScoreAt = 0L;

    GameView(Context context) {
        super(context);
        setFocusable(true);
        setKeepScreenOn(true);
        for (int i = 0; i < HOLES; i++) {
            cells[i] = new RectF();
            holeOvals[i] = new RectF();
        }
        prefs = context.getSharedPreferences("whac_state", Context.MODE_PRIVATE);
        best = prefs.getInt("best_score", 0);
        bestStreak = prefs.getInt("best_streak", 0);
        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextAlign(Paint.Align.CENTER);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeCap(Paint.Cap.ROUND);
    }

    void onShown() {
        lastFrameAt = 0L;
        invalidate();
    }

    void onHidden() {
        lastFrameAt = 0L;
    }

    // ---------------------------------------------------------------- 布局

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        layout(w, h);
    }

    private void layout(int w, int h) {
        viewW = w;
        viewH = h;
        float min = Math.min(w, h);
        margin = Math.max(min * 0.020f, 12f);
        gap = Math.max(min * 0.016f, 10f);
        landscape = w >= h * 1.15f;

        if (landscape) {
            float sideW = clamp(w * 0.33f, w * 0.26f, w * 0.40f);
            panel.set(margin, margin, margin + sideW, h - margin);

            float left = panel.right + gap;
            float availW = w - margin - left;
            float availH = h - margin * 2f;
            float side = Math.min(availW, availH);
            float bx = left + (availW - side) * 0.5f;
            float by = margin + (availH - side) * 0.5f;
            boardRect.set(bx, by, bx + side, by + side);
        } else {
            float panelH = clamp(h * 0.22f, h * 0.16f, h * 0.28f);
            panel.set(margin, margin, w - margin, margin + panelH);

            float top = panel.bottom + gap;
            float footH = clamp(h * 0.14f, h * 0.10f, h * 0.20f);
            float availW = w - margin * 2f;
            float availH = h - margin - footH - top;
            float side = Math.max(Math.min(availW, availH), 1f);
            float bx = (w - side) * 0.5f;
            float by = top + Math.max((availH - side) * 0.5f, 0f);
            boardRect.set(bx, by, bx + side, by + side);
        }

        float cw = boardRect.width() / COLS;
        float ch = boardRect.height() / ROWS;
        float inX = cw * 0.045f;
        float inY = ch * 0.045f;
        for (int r = 0; r < ROWS; r++) {
            for (int c = 0; c < COLS; c++) {
                int i = r * COLS + c;
                cells[i].set(boardRect.left + c * cw + inX,
                        boardRect.top + r * ch + inY,
                        boardRect.left + (c + 1) * cw - inX,
                        boardRect.top + (r + 1) * ch - inY);

                float ow = cells[i].width() * 0.74f;
                float oh = cells[i].height() * 0.30f;
                float cx = cells[i].centerX();
                float cy = cells[i].bottom - cells[i].height() * 0.28f;
                holeOvals[i].set(cx - ow * 0.5f, cy - oh * 0.5f, cx + ow * 0.5f, cy + oh * 0.5f);
            }
        }

        if (landscape) {
            float bh = Math.max(panel.height() * 0.115f, 78f);
            float bw = panel.width() * 0.85f;
            float bx = panel.centerX() - bw * 0.5f;
            float by = panel.bottom - panel.height() * 0.075f - bh;
            button.set(bx, by, bx + bw, by + bh);
        } else {
            float bh = Math.max(h * 0.095f, 84f);
            float bw = Math.min(w * 0.48f, 760f);
            float bcy = boardRect.bottom + (h - margin - boardRect.bottom) * 0.5f;
            button.set(w * 0.5f - bw * 0.5f, bcy - bh * 0.5f, w * 0.5f + bw * 0.5f, bcy + bh * 0.5f);
        }

        bgShader = new LinearGradient(0f, 0f, w * 0.30f, h, BG_A, BG_B, Shader.TileMode.CLAMP);
        float glowR = Math.max(boardRect.width() * 0.85f, 64f);
        glowShader = new RadialGradient(boardRect.centerX(), boardRect.centerY(), glowR,
                0x2E57A76A, 0x00000000, Shader.TileMode.CLAMP);
    }

    private float boardRadius() {
        return Math.max(boardRect.width() * 0.030f, 16f);
    }

    // ---------------------------------------------------------------- 主循环

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        long now = SystemClock.uptimeMillis();
        long dt = 0L;
        if (state == State.RUNNING) {
            dt = (lastFrameAt == 0L) ? 0L : Math.min(now - lastFrameAt, 100L);
        }
        lastFrameAt = now;

        if (state == State.RUNNING) {
            step(dt, now);
        }
        if (flashIndex >= 0 && now - flashAt >= FLASH_MS) {
            flashIndex = -1;
        }
        if (hammerAt > 0L && now - hammerAt >= HAMMER_MS) {
            hammerAt = 0L;
        }
        if (struckCell >= 0 && now - struckAt >= CRACK_MS) {
            struckCell = -1;
        }
        if (dustAt > 0L && now - dustAt >= DUST_MS) {
            dustAt = 0L;
        }
        if (popScoreAt > 0L && now - popScoreAt >= SCORE_POP_MS) {
            popScoreAt = 0L;
        }

        drawBackground(canvas);
        drawBoard(canvas);
        if (landscape) {
            drawSidePanel(canvas);
        } else {
            drawTopPanel(canvas);
        }
        if (state == State.READY) {
            drawReadyOverlay(canvas);
        } else if (state == State.OVER) {
            drawOverOverlay(canvas);
        }
        drawScorePop(canvas, now);

        boolean anim = state == State.RUNNING
                || hammerAt > 0L
                || struckCell >= 0
                || flashIndex >= 0
                || dustAt > 0L
                || popScoreAt > 0L;
        if (anim) {
            postInvalidateOnAnimation();
        }
    }

    private void step(long dt, long now) {
        timeLeftMs -= dt;
        if (timeLeftMs <= 0L) {
            timeLeftMs = 0L;
            finishGame(now);
            return;
        }
        if (moleIndex < 0) {
            pop = 0f;
            if (nextMoleAt == 0L || now >= nextMoleAt) {
                spawnMole(now);
            }
            return;
        }
        long life = moleSinkAt - moleRiseAt;
        long age = now - moleRiseAt;
        long left = moleSinkAt - now;
        float rise = life <= 0L ? 1f : clamp01(age / (float) POP_MS);
        float sink = clamp01(left / (float) POP_MS);
        pop = Math.min(rise, sink);
        if (left <= 0L) {
            moleIndex = -1;
            pop = 0f;
            misses++;
            streak = 0;
            nextMoleAt = now + gapMs();
        }
    }

    private long gapMs() {
        return GAP_MIN_MS + (long) (random.nextDouble() * (GAP_MAX_MS - GAP_MIN_MS));
    }

    private void spawnMole(long now) {
        int idx = random.nextInt(HOLES);
        if (lastMoleIndex >= 0 && idx == lastMoleIndex) {
            idx = (idx + 1 + random.nextInt(HOLES - 1)) % HOLES;
        }
        lastMoleIndex = idx;
        moleIndex = idx;
        moleRiseAt = now;
        moleSinkAt = now + LIFE_MIN_MS + (long) (random.nextDouble() * (LIFE_MAX_MS - LIFE_MIN_MS));
        pop = 0f;
    }

    private void startGame(long now) {
        state = State.RUNNING;
        score = 0;
        hits = 0;
        misses = 0;
        streak = 0;
        newRecord = false;
        timeLeftMs = GAME_MS;
        moleIndex = -1;
        lastMoleIndex = -1;
        pop = 0f;
        flashIndex = -1;
        struckCell = -1;
        hammerAt = 0L;
        dustAt = 0L;
        popScoreAt = 0L;
        nextMoleAt = now + FIRST_MOLE_MS;
        lastFrameAt = 0L;
        invalidate();
    }

    private void finishGame(long now) {
        state = State.OVER;
        overAt = now;
        moleIndex = -1;
        pop = 0f;
        if (streak > bestStreak) {
            bestStreak = streak;
        }
        if (bestStreak > prefs.getInt("best_streak", 0)) {
            prefs.edit().putInt("best_streak", bestStreak).apply();
        }
        newRecord = score > best;
        if (newRecord) {
            best = score;
            prefs.edit().putInt("best_score", best).apply();
        }
    }

    // ---------------------------------------------------------------- 触摸

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getActionMasked() != MotionEvent.ACTION_DOWN) {
            return true;
        }
        long now = SystemClock.uptimeMillis();
        float x = event.getX();
        float y = event.getY();

        if (button.contains(x, y)) {
            if (state == State.READY) {
                startGame(now);
            } else if (state == State.OVER && now - overAt >= RESTART_GUARD_MS) {
                startGame(now);
            }
            return true;
        }
        if (state == State.READY) {
            if (boardRect.contains(x, y)) {
                startGame(now);
            }
            return true;
        }
        if (state == State.OVER) {
            if (boardRect.contains(x, y) && now - overAt >= RESTART_GUARD_MS) {
                startGame(now);
            }
            return true;
        }
        whack(x, y, now);
        return true;
    }

    private void whack(float x, float y, long now) {
        if (!boardRect.contains(x, y)) {
            return;
        }
        int cell = cellAt(x, y);
        if (cell < 0) {
            return;
        }
        float r = moleRadius(cell);
        boolean hit = moleIndex >= 0 && cell == moleIndex && pop >= HIT_MIN_POP;
        float holeCx = holeOvals[cell].centerX();
        float hx;
        float hy;
        if (hit) {
            float headY = moleHeadY(cell, pop);
            hx = holeCx + clamp(x - holeCx, -r * 0.45f, r * 0.45f) * 0.55f;
            hy = headY + clamp(y - headY, -r * 0.40f, r * 0.40f) * 0.55f;
        } else {
            hx = x;
            hy = y;
        }

        hammerAt = now;
        hammerHit = hit;
        hammerX = hx;
        hammerY = hy;
        hammerR = hit ? r : r * 0.85f;

        if (hit) {
            struckCell = cell;
            struckAt = now;
            struckPop = pop;
            crackX = hx;
            crackY = hy;
            crackR = r;
            flashIndex = cell;
            flashAt = now;
            score += HIT_SCORE;
            hits++;
            streak++;
            if (streak > bestStreak) {
                bestStreak = streak;
            }
            popScore = HIT_SCORE;
            popScoreX = hx;
            popScoreY = hy - r * 0.95f;
            popScoreAt = now;
            moleIndex = -1;
            pop = 0f;
            nextMoleAt = now + gapMs();
        } else {
            streak = 0;
            dustAt = now;
            dustX = x;
            dustY = y;
            dustCell = cell;
        }
        invalidate();
    }

    private int cellAt(float x, float y) {
        for (int i = 0; i < HOLES; i++) {
            if (cells[i].contains(x, y)) {
                return i;
            }
        }
        return -1;
    }

    private float moleRadius(int index) {
        RectF cell = cells[index];
        return Math.min(cell.width() * 0.27f, cell.height() * 0.30f);
    }

    private float moleCenterY(int index, float popValue) {
        float r = moleRadius(index);
        float holeCy = holeOvals[index].centerY();
        float lowCy = holeCy + r * 0.95f;
        float highCy = holeCy - r * 0.80f;
        return lowCy + (highCy - lowCy) * popValue;
    }

    private float moleHeadY(int index, float popValue) {
        return moleCenterY(index, popValue) - moleRadius(index) * 0.30f;
    }

    // ---------------------------------------------------------------- 绘制

    private void drawBackground(Canvas c) {
        fill.setStyle(Paint.Style.FILL);
        fill.setShader(bgShader);
        c.drawRect(0f, 0f, viewW, viewH, fill);
        fill.setShader(glowShader);
        c.drawRect(0f, 0f, viewW, viewH, fill);
        fill.setShader(null);
    }

    private void drawBoard(Canvas c) {
        float radius = boardRadius();
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(BOARD_FILL);
        c.drawRoundRect(boardRect, radius, radius, fill);

        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(2.5f, boardRect.width() * 0.0035f));
        stroke.setColor(BOARD_EDGE);
        c.drawRoundRect(boardRect, radius, radius, stroke);

        // 倒计时告急：板面内脉冲红框（内缩描边，不遮挡内容）
        if (state == State.RUNNING && timeLeftMs <= URGENT_MS) {
            float pulse = 0.5f + 0.5f * (float) Math.sin(SystemClock.uptimeMillis() / 170.0);
            float sw = Math.max(4f, boardRect.width() * 0.008f);
            stroke.setStrokeWidth(sw);
            stroke.setColor(Color.argb((int) (80 + 130 * pulse), 0xFF, 0x6B, 0x6B));
            tmp.set(boardRect);
            tmp.inset(sw * 0.7f, sw * 0.7f);
            c.drawRoundRect(tmp, radius, radius, stroke);
        }

        for (int i = 0; i < HOLES; i++) {
            RectF cell = cells[i];
            float cr = Math.max(cell.width() * 0.10f, 10f);
            fill.setStyle(Paint.Style.FILL);
            fill.setColor(TILE_FILL);
            c.drawRoundRect(cell, cr, cr, fill);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeWidth(Math.max(2f, cell.width() * 0.006f));
            stroke.setColor(TILE_EDGE);
            c.drawRoundRect(cell, cr, cr, stroke);

            RectF oval = holeOvals[i];
            RectF mound = new RectF(oval);
            mound.inset(-oval.width() * 0.06f, -oval.height() * 0.34f);
            fill.setStyle(Paint.Style.FILL);
            fill.setColor(GRASS);
            c.drawOval(mound, fill);
            fill.setColor(HOLE_DARK);
            c.drawOval(oval, fill);

            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeWidth(Math.max(2f, oval.height() * 0.10f));
            stroke.setColor(0x5537A055);
            c.drawOval(oval, stroke);
        }

        long now = SystemClock.uptimeMillis();

        // 刚被击中的地鼠：缩回 + 头部裂纹慢慢恢复
        if (struckCell >= 0) {
            float t = clamp01((now - struckAt) / (float) STRUCK_MS);
            float pv = Math.max(0.10f, struckPop * (1f - 0.78f * t));
            drawMole(c, struckCell, pv, 1f - 0.30f * t);
            drawCracks(c, struckCell, now - struckAt);
        }

        if (moleIndex >= 0 && pop > 0.01f) {
            drawMole(c, moleIndex, pop, 1f);
        }

        // 洞口近侧壁盖住地鼠下半身，形成“从洞里冒出来”的效果
        for (int i = 0; i < HOLES; i++) {
            RectF oval = holeOvals[i];
            c.save();
            c.clipRect(cells[i].left - 4f, oval.centerY(), cells[i].right + 4f, oval.bottom + 8f);
            fill.setStyle(Paint.Style.FILL);
            fill.setColor(HOLE_LIP);
            c.drawOval(oval, fill);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeWidth(Math.max(2.5f, oval.height() * 0.12f));
            stroke.setColor(GRASS_RIM);
            c.drawOval(oval, stroke);
            c.restore();
        }

        if (flashIndex >= 0) {
            float k = clamp01(1f - (now - flashAt) / (float) FLASH_MS);
            RectF oval = holeOvals[flashIndex];
            RectF ring = new RectF(oval);
            ring.inset(-oval.width() * 0.05f, -oval.height() * 0.22f);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeWidth(Math.max(3f, oval.height() * 0.16f));
            stroke.setColor(Color.argb((int) (210f * k * k), 0x8B, 0xF5, 0xB0));
            c.drawOval(ring, stroke);
        }

        drawDust(c, now);
        drawHammer(c, now);
    }

    private void drawMole(Canvas c, int index, float popValue, float alphaScale) {
        RectF cell = cells[index];
        float r = moleRadius(index);
        float cx = holeOvals[index].centerX();
        float holeCy = holeOvals[index].centerY();
        float cy = moleCenterY(index, popValue);
        int a = (int) (255f * clamp01(alphaScale));
        if (a <= 4) {
            return;
        }

        boolean layer = a < 250;
        if (layer) {
            c.saveLayerAlpha(cell.left - 4f, cell.top - 4f,
                    cell.right + 4f, holeCy + r * 0.20f, a, Canvas.ALL_SAVE_FLAG);
        }
        c.save();
        c.clipRect(cell.left - 2f, cell.top - 2f, cell.right + 2f, holeCy + r * 0.06f);

        // 耳朵
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(MOLE_EAR);
        c.drawCircle(cx - r * 0.74f, cy - r * 0.60f, r * 0.30f, fill);
        c.drawCircle(cx + r * 0.74f, cy - r * 0.60f, r * 0.30f, fill);
        fill.setColor(MOLE_PINK);
        c.drawCircle(cx - r * 0.74f, cy - r * 0.60f, r * 0.15f, fill);
        c.drawCircle(cx + r * 0.74f, cy - r * 0.60f, r * 0.15f, fill);

        // 头 / 身体（浅色高光制造体积感）
        fill.setColor(MOLE_FUR);
        c.drawCircle(cx, cy, r, fill);
        fill.setColor(MOLE_FUR_HI);
        c.drawCircle(cx - r * 0.18f, cy - r * 0.24f, r * 0.60f, fill);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(2f, r * 0.055f));
        stroke.setColor(MOLE_EDGE);
        c.drawCircle(cx, cy, r, stroke);

        // 口鼻
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(MOLE_SNOUT);
        tmp.set(cx - r * 0.50f, cy + r * 0.06f, cx + r * 0.50f, cy + r * 0.78f);
        c.drawOval(tmp, fill);

        if (popValue > 0.22f) {
            float ey = cy - r * 0.16f;
            float ex = r * 0.34f;
            fill.setColor(Color.WHITE);
            c.drawCircle(cx - ex, ey, r * 0.20f, fill);
            c.drawCircle(cx + ex, ey, r * 0.20f, fill);
            fill.setColor(0xFF241A14);
            c.drawCircle(cx - ex, ey + r * 0.02f, r * 0.095f, fill);
            c.drawCircle(cx + ex, ey + r * 0.02f, r * 0.095f, fill);
            fill.setColor(Color.WHITE);
            c.drawCircle(cx - ex + r * 0.04f, ey - r * 0.05f, r * 0.035f, fill);
            c.drawCircle(cx + ex + r * 0.04f, ey - r * 0.05f, r * 0.035f, fill);

            fill.setColor(MOLE_PINK);
            c.drawCircle(cx, cy + r * 0.26f, r * 0.135f, fill);
            fill.setColor(0x66FFFFFF);
            c.drawCircle(cx - r * 0.04f, cy + r * 0.22f, r * 0.05f, fill);

            path.reset();
            path.moveTo(cx - r * 0.20f, cy + r * 0.44f);
            path.quadTo(cx, cy + r * 0.62f, cx + r * 0.20f, cy + r * 0.44f);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeCap(Paint.Cap.ROUND);
            stroke.setStrokeWidth(Math.max(1.8f, r * 0.055f));
            stroke.setColor(0xFF4E342E);
            c.drawPath(path, stroke);

            stroke.setStrokeWidth(Math.max(1.4f, r * 0.035f));
            stroke.setColor(0xFF5C4433);
            c.drawLine(cx - r * 0.40f, cy + r * 0.28f, cx - r * 0.98f, cy + r * 0.16f, stroke);
            c.drawLine(cx - r * 0.40f, cy + r * 0.42f, cx - r * 0.98f, cy + r * 0.50f, stroke);
            c.drawLine(cx + r * 0.40f, cy + r * 0.28f, cx + r * 0.98f, cy + r * 0.16f, stroke);
            c.drawLine(cx + r * 0.40f, cy + r * 0.42f, cx + r * 0.98f, cy + r * 0.50f, stroke);
        }

        c.restore();
        if (layer) {
            c.restore();
        }
    }

    /**
     * 命中地鼠头部后的局部裂纹：先在头部位置长出，随后逐渐收拢、变淡，直至完全恢复。
     * 只在被击中的单元格内绘制，绝不溢出到按钮或计分区域。
     */
    private void drawCracks(Canvas c, int cellIndex, long age) {
        float p = clamp01(age / (float) CRACK_MS);
        float grow = clamp01(p / 0.05f);
        float extent = (1f - 0.82f * p) * grow;
        float alpha = 240f * (float) Math.pow(1f - p, 1.35);
        if (alpha < 6f || extent <= 0.01f) {
            return;
        }
        int a = (int) Math.min(255f, alpha);
        float x = crackX;
        float y = crackY;
        float r = crackR;

        c.save();
        c.clipRect(cells[cellIndex]);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        stroke.setStrokeWidth(Math.max(1.8f, r * 0.05f) * (1f - 0.30f * p));
        stroke.setColor(Color.argb(a, 0xF2, 0xFA, 0xFF));
        for (int i = 0; i < 9; i++) {
            double ang = i * (Math.PI * 2.0 / 9.0) - 0.20 + ((i * 37) % 7 - 3) * 0.035;
            float dx = (float) Math.cos(ang);
            float dy = (float) Math.sin(ang);
            float sx = -dy;
            float sy = dx;
            float end = r * (0.82f + (i % 3) * 0.16f) * extent;
            path.reset();
            path.moveTo(x, y);
            path.lineTo(x + dx * end * 0.34f + sx * r * 0.09f,
                    y + dy * end * 0.34f + sy * r * 0.09f);
            path.lineTo(x + dx * end * 0.70f - sx * r * 0.07f,
                    y + dy * end * 0.70f - sy * r * 0.07f);
            path.lineTo(x + dx * end, y + dy * end);
            c.drawPath(path, stroke);
            if (i % 2 == 0) {
                c.drawLine(x + dx * end * 0.70f - sx * r * 0.07f,
                        y + dy * end * 0.70f - sy * r * 0.07f,
                        x + dx * end * 0.76f + sx * r * 0.20f,
                        y + dy * end * 0.76f + sy * r * 0.20f, stroke);
            }
        }
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(Color.argb((int) (110f * (1f - p)), 0xFF, 0xFF, 0xFF));
        c.drawCircle(x, y, Math.max(2.5f, r * 0.13f * extent), fill);
        c.restore();
    }

    private void drawHammer(Canvas c, long now) {
        if (hammerAt == 0L) {
            return;
        }
        float age = now - hammerAt;
        if (age < 0f || age >= HAMMER_MS) {
            return;
        }
        float r = hammerR;
        float strike = clamp01(age / 110f);
        float lift = clamp01((age - 230f) / 190f);
        int a = (int) (255f * (1f - lift));
        if (a <= 4) {
            return;
        }

        c.save();
        c.translate(hammerX + r * 0.55f * (1f - strike) + r * 0.26f * lift,
                hammerY - r * 0.72f * (1f - strike) - r * 0.50f * lift);
        c.rotate(-36f * (1f - strike) + 24f * lift);

        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        stroke.setStrokeWidth(Math.max(7f, r * 0.22f));
        stroke.setColor(Color.argb(a, 0x8A, 0x5A, 0x38));
        c.drawLine(r * 0.24f, -r * 0.16f, r * 1.16f, -r * 1.06f, stroke);

        fill.setStyle(Paint.Style.FILL);
        fill.setColor(Color.argb(a, hammerHit ? 0xEA : 0xC6, hammerHit ? 0xF1 : 0xD0, hammerHit ? 0xF7 : 0xD8));
        RectF head = new RectF(-r * 0.60f, -r * 0.42f, r * 0.48f, r * 0.16f);
        c.drawRoundRect(head, r * 0.13f, r * 0.13f, fill);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(2f, r * 0.055f));
        stroke.setColor(Color.argb(a, 0x54, 0x66, 0x72));
        c.drawRoundRect(head, r * 0.13f, r * 0.13f, stroke);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(Color.argb((int) (a * 0.55f), 0xFF, 0xFF, 0xFF));
        RectF hl = new RectF(-r * 0.52f, -r * 0.34f, r * 0.40f, -r * 0.18f);
        c.drawRoundRect(hl, r * 0.09f, r * 0.09f, fill);
        c.restore();

        if (hammerHit && age < 160f) {
            float k = 1f - clamp01(age / 160f);
            float len = r * (0.90f + 0.50f * (1f - k));
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeCap(Paint.Cap.ROUND);
            stroke.setStrokeWidth(Math.max(2.5f, r * 0.07f));
            stroke.setColor(Color.argb((int) (220f * k), 0xFF, 0xF2, 0xB0));
            for (int i = 0; i < 6; i++) {
                double ang = i * Math.PI / 3.0 + 0.30;
                float dx = (float) Math.cos(ang);
                float dy = (float) Math.sin(ang);
                c.drawLine(hammerX + dx * r * 0.30f, hammerY + dy * r * 0.30f,
                        hammerX + dx * len, hammerY + dy * len, stroke);
            }
        }
    }

    private void drawDust(Canvas c, long now) {
        if (dustAt == 0L) {
            return;
        }
        float t = clamp01((now - dustAt) / (float) DUST_MS);
        if (t >= 1f) {
            return;
        }
        int a = (int) (170f * (1f - t));
        float r = Math.max(viewW, viewH) * 0.012f;
        c.save();
        if (dustCell >= 0) {
            c.clipRect(cells[dustCell]);
        }
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        stroke.setStrokeWidth(Math.max(2f, r * 0.28f));
        stroke.setColor(Color.argb(a, 0xD8, 0xCB, 0xA8));
        for (int i = 0; i < 5; i++) {
            double ang = Math.PI + i * (Math.PI / 4.0);
            float dx = (float) Math.cos(ang);
            float dy = (float) Math.sin(ang);
            float r0 = r * 0.40f;
            float r1 = r * (1.0f + 2.2f * t);
            c.drawLine(dustX + dx * r0, dustY + dy * r0,
                    dustX + dx * r1, dustY + dy * r1, stroke);
        }
        c.restore();
    }

    private void drawScorePop(Canvas c, long now) {
        if (popScoreAt == 0L) {
            return;
        }
        float t = clamp01((now - popScoreAt) / (float) SCORE_POP_MS);
        int a = (int) (255f * (1f - t));
        if (a <= 4) {
            return;
        }
        c.save();
        c.clipRect(boardRect);
        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(Math.max(boardRect.height() * 0.055f, 20f));
        textPaint.setColor(Color.argb(a, 0xFF, 0xE0, 0x82));
        c.drawText("+" + popScore, popScoreX, popScoreY - t * boardRect.height() * 0.09f, textPaint);
        c.restore();
    }

    // ---------------------------------------------------------------- 信息栏与按钮

    private void drawPanelBackground(Canvas c, RectF r) {
        float radius = Math.max(r.height() * 0.03f, 16f);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(PANEL_FILL);
        c.drawRoundRect(r, radius, radius, fill);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(2f, r.height() * 0.0035f));
        stroke.setColor(PANEL_EDGE);
        c.drawRoundRect(r, radius, radius, stroke);
    }

    private void drawCard(Canvas c, RectF r, String label, String value, int valueColor,
                          float labelSize, float valueSize) {
        float radius = Math.max(r.height() * 0.22f, 10f);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(CARD_FILL);
        c.drawRoundRect(r, radius, radius, fill);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(1.8f, r.height() * 0.018f));
        stroke.setColor(CARD_EDGE);
        c.drawRoundRect(r, radius, radius, stroke);

        float padX = r.height() * 0.30f;
        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextAlign(Paint.Align.LEFT);
        textPaint.setTextSize(labelSize);
        textPaint.setColor(TEXT_LABEL);
        float labelBaseline = r.top + labelSize * 1.35f;
        c.drawText(label, r.left + padX, labelBaseline, textPaint);

        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextSize(valueSize);
        textPaint.setColor(valueColor);
        c.drawText(value, r.left + padX, labelBaseline + valueSize * 1.12f, textPaint);
    }

    private void drawTimeCard(Canvas c, RectF r, float labelSize, float valueSize) {
        float radius = Math.max(r.height() * 0.22f, 10f);
        boolean urgent = state == State.RUNNING && timeLeftMs <= URGENT_MS;
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(CARD_FILL);
        c.drawRoundRect(r, radius, radius, fill);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(1.8f, r.height() * 0.018f));
        stroke.setColor(urgent ? DANGER : CARD_EDGE);
        c.drawRoundRect(r, radius, radius, stroke);

        float padX = r.height() * 0.30f;
        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextAlign(Paint.Align.LEFT);
        textPaint.setTextSize(labelSize);
        textPaint.setColor(TEXT_LABEL);
        float labelBaseline = r.top + labelSize * 1.35f;
        c.drawText("倒计时", r.left + padX, labelBaseline, textPaint);

        int secs = (int) ((timeLeftMs + 999L) / 1000L);
        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextSize(valueSize);
        textPaint.setColor(urgent ? DANGER : ACCENT);
        float valueBaseline = labelBaseline + valueSize * 1.12f;
        c.drawText(String.valueOf(secs), r.left + padX, valueBaseline, textPaint);

        float numW = textPaint.measureText(String.valueOf(secs));
        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextSize(Math.max(labelSize, 12f));
        textPaint.setColor(TEXT_DIM);
        c.drawText("秒", r.left + padX + numW + labelSize * 0.35f, valueBaseline, textPaint);

        float barH = Math.max(r.height() * 0.075f, 6f);
        float barTop = r.bottom - barH * 1.7f;
        RectF bar = new RectF(r.left + padX, barTop, r.right - padX, barTop + barH);
        float frac = clamp01(timeLeftMs / (float) GAME_MS);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(0xFF08170E);
        c.drawRoundRect(bar, barH * 0.5f, barH * 0.5f, fill);
        float wFill = Math.max(bar.width() * frac, barH);
        RectF barFill = new RectF(bar.left, bar.top,
                Math.min(bar.left + wFill, bar.right), bar.bottom);
        fill.setColor(urgent ? DANGER : ACCENT);
        c.drawRoundRect(barFill, barH * 0.5f, barH * 0.5f, fill);
    }

    private void drawStatsCard(Canvas c, RectF r, float labelSize, float valueSize) {
        float radius = Math.max(r.height() * 0.26f, 10f);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(CARD_FILL);
        c.drawRoundRect(r, radius, radius, fill);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(1.8f, r.height() * 0.022f));
        stroke.setColor(CARD_EDGE);
        c.drawRoundRect(r, radius, radius, stroke);

        float padX = r.height() * 0.34f;
        float labelBaseline = r.top + labelSize * 1.45f;
        float valueBaseline = r.bottom - valueSize * 0.30f;

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextSize(labelSize);
        textPaint.setColor(TEXT_LABEL);
        textPaint.setTextAlign(Paint.Align.LEFT);
        c.drawText("命中", r.left + padX, labelBaseline, textPaint);
        textPaint.setTextAlign(Paint.Align.RIGHT);
        c.drawText("漏掉", r.right - padX, labelBaseline, textPaint);

        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextSize(valueSize);
        textPaint.setTextAlign(Paint.Align.LEFT);
        textPaint.setColor(HIT_GREEN);
        c.drawText(String.valueOf(hits), r.left + padX, valueBaseline, textPaint);
        textPaint.setTextAlign(Paint.Align.RIGHT);
        textPaint.setColor(MISS_PINK);
        c.drawText(String.valueOf(misses), r.right - padX, valueBaseline, textPaint);

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextSize(labelSize * 0.92f);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setColor(streak >= 3 ? ACCENT : TEXT_DIM);
        c.drawText("连击 x" + streak, r.centerX(), valueBaseline, textPaint);
    }

    private void drawSidePanel(Canvas c) {
        drawPanelBackground(c, panel);
        float ph = panel.height();
        float pw = panel.width();

        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextAlign(Paint.Align.LEFT);
        textPaint.setTextSize(Math.max(ph * 0.052f, 18f));
        textPaint.setColor(TEXT_MAIN);
        c.drawText("打 地 鼠", panel.left + pw * 0.075f, panel.top + ph * 0.085f, textPaint);

        float subSize = Math.max(ph * 0.026f, 12f);
        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextSize(subSize);
        textPaint.setColor(TEXT_DIM);
        c.drawText("九宫格 · 60 秒 · 每只 " + HIT_SCORE + " 分",
                panel.left + pw * 0.075f, panel.top + ph * 0.085f + subSize * 1.9f, textPaint);

        float px = panel.left + pw * 0.075f;
        float cw = pw * 0.85f;
        float top = panel.top + ph * 0.135f;
        float scoreH = ph * 0.135f;
        float timeH = ph * 0.200f;
        float statH = ph * 0.100f;
        float bestH = ph * 0.115f;
        float cg = ph * 0.028f;

        tmp.set(px, top, px + cw, top + scoreH);
        drawCard(c, tmp, "得分", String.valueOf(score), TEXT_MAIN, scoreH * 0.19f, scoreH * 0.45f);
        top += scoreH + cg;

        tmp.set(px, top, px + cw, top + timeH);
        drawTimeCard(c, tmp, timeH * 0.14f, timeH * 0.34f);
        top += timeH + cg;

        tmp.set(px, top, px + cw, top + statH);
        drawStatsCard(c, tmp, statH * 0.19f, statH * 0.38f);
        top += statH + cg;

        tmp.set(px, top, px + cw, top + bestH);
        drawCard(c, tmp, "最高分", String.valueOf(best),
                newRecord ? ACCENT : TEXT_MAIN, bestH * 0.19f, bestH * 0.42f);

        drawButton(c);

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(Math.max(ph * 0.024f, 12f));
        textPaint.setColor(TEXT_DIM);
        c.drawText(hintText(), panel.centerX(),
                Math.min(button.bottom + Math.max(ph * 0.038f, 18f), panel.bottom - 6f), textPaint);
    }

    private void drawTopPanel(Canvas c) {
        drawPanelBackground(c, panel);
        float ph = panel.height();
        float px = panel.left + panel.width() * 0.035f;
        float pw = panel.width() * 0.93f;
        float cgx = panel.width() * 0.025f;
        float cw = (pw - cgx * 2f) / 3f;
        float ch = ph * 0.64f;
        float top = panel.top + ph * 0.09f;
        float labelSize = Math.max(ch * 0.19f, 11f);
        float valueSize = Math.max(ch * 0.44f, 18f);

        tmp.set(px, top, px + cw, top + ch);
        drawCard(c, tmp, "得分", String.valueOf(score), TEXT_MAIN, labelSize, valueSize);
        tmp.set(px + cw + cgx, top, px + cw * 2f + cgx, top + ch);
        drawTimeCard(c, tmp, labelSize, valueSize);
        tmp.set(px + (cw + cgx) * 2f, top, px + pw, top + ch);
        drawCard(c, tmp, "最高分", String.valueOf(best),
                newRecord ? ACCENT : TEXT_MAIN, labelSize, valueSize);

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(Math.max(ph * 0.10f, 12f));
        textPaint.setColor(TEXT_DIM);
        c.drawText("命中 " + hits + " · 漏掉 " + misses + " · 连击 x" + streak,
                panel.centerX(), panel.bottom - ph * 0.06f, textPaint);

        drawButton(c);

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(Math.max(ph * 0.11f, 12f));
        textPaint.setColor(TEXT_DIM);
        c.drawText(hintText(), button.centerX(),
                Math.min(button.bottom + Math.max(ph * 0.16f, 16f), viewH - margin * 0.5f), textPaint);
    }

    private void drawButton(Canvas c) {
        boolean enabled = state != State.RUNNING;
        float radius = Math.max(button.height() * 0.26f, 12f);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(enabled ? ACCENT : BTN_OFF_FILL);
        c.drawRoundRect(button, radius, radius, fill);

        if (enabled) {
            RectF hl = new RectF(button);
            hl.inset(button.width() * 0.03f, button.height() * 0.10f);
            hl.bottom = button.centerY() - button.height() * 0.06f;
            fill.setColor(0x33FFFFFF);
            c.drawRoundRect(hl, radius, radius, fill);
        }

        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(2.5f, button.height() * 0.045f));
        stroke.setColor(enabled ? ACCENT_EDGE : BTN_OFF_EDGE);
        c.drawRoundRect(button, radius, radius, stroke);

        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(button.height() * 0.40f);
        textPaint.setColor(enabled ? ACCENT_TEXT : BTN_OFF_TEXT);
        float baseline = button.centerY() - (textPaint.descent() + textPaint.ascent()) * 0.5f;
        c.drawText(buttonLabel(), button.centerX(), baseline, textPaint);
    }

    private String buttonLabel() {
        if (state == State.READY) {
            return "开始游戏";
        }
        if (state == State.RUNNING) {
            return "进行中";
        }
        return "重新开始";
    }

    private String hintText() {
        if (state == State.READY) {
            return "点按板面或按钮开始游戏";
        }
        if (state == State.RUNNING) {
            return "锤击地鼠头部 +" + HIT_SCORE + " 分 · 裂纹会慢慢恢复";
        }
        return "点按板面或按钮再来一局";
    }

    // ---------------------------------------------------------------- 提示卡（只在板面内）

    private void drawModalCard(Canvas c, RectF r) {
        float radius = Math.max(r.height() * 0.08f, 14f);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(0xF21B3A26);
        c.drawRoundRect(r, radius, radius, fill);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(Math.max(2.5f, r.height() * 0.012f));
        stroke.setColor(0xFF3C7A52);
        c.drawRoundRect(r, radius, radius, stroke);
    }

    private void drawReadyOverlay(Canvas c) {
        float radius = boardRadius();
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(0xB806130B);
        c.drawRoundRect(boardRect, radius, radius, fill);

        float w = boardRect.width() * 0.62f;
        float h = boardRect.height() * 0.34f;
        tmp.set(boardRect.centerX() - w * 0.5f, boardRect.centerY() - h * 0.5f,
                boardRect.centerX() + w * 0.5f, boardRect.centerY() + h * 0.5f);
        drawModalCard(c, tmp);

        float cx = tmp.centerX();
        float titleSize = tmp.height() * 0.24f;
        float subSize = tmp.height() * 0.105f;

        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(titleSize);
        textPaint.setColor(TEXT_MAIN);
        float y = tmp.top + titleSize * 1.25f;
        c.drawText("打 地 鼠", cx, y, textPaint);

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextSize(subSize);
        textPaint.setColor(TEXT_LABEL);
        y += subSize * 2.0f;
        c.drawText("60 秒倒计时 · 九宫格地鼠 · 每只 " + HIT_SCORE + " 分", cx, y, textPaint);

        textPaint.setColor(TEXT_DIM);
        y += subSize * 1.8f;
        c.drawText("命中头部会出现裂纹并逐渐恢复", cx, y, textPaint);

        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setColor(ACCENT);
        y += subSize * 2.0f;
        c.drawText("最高分 " + best, cx, y, textPaint);
    }

    private void drawOverOverlay(Canvas c) {
        float radius = boardRadius();
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(0xC806130B);
        c.drawRoundRect(boardRect, radius, radius, fill);

        float w = boardRect.width() * 0.68f;
        float h = boardRect.height() * 0.48f;
        tmp.set(boardRect.centerX() - w * 0.5f, boardRect.centerY() - h * 0.5f,
                boardRect.centerX() + w * 0.5f, boardRect.centerY() + h * 0.5f);
        drawModalCard(c, tmp);

        float cx = tmp.centerX();
        float titleSize = tmp.height() * 0.145f;
        float scoreSize = tmp.height() * 0.290f;
        float smallSize = tmp.height() * 0.078f;

        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(titleSize);
        textPaint.setColor(TEXT_MAIN);
        float y = tmp.top + tmp.height() * 0.18f;
        c.drawText("时 间 到", cx, y, textPaint);

        textPaint.setTextSize(scoreSize);
        textPaint.setColor(ACCENT);
        y += scoreSize * 1.12f;
        c.drawText(String.valueOf(score), cx, y, textPaint);

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setTextSize(smallSize);
        textPaint.setColor(TEXT_LABEL);
        y += smallSize * 2.2f;
        c.drawText("命中 " + hits + " 只 · 漏掉 " + misses + " 只 · 最长连击 x" + bestStreak,
                cx, y, textPaint);

        y += smallSize * 1.5f;
        if (newRecord) {
            textPaint.setTypeface(Typeface.DEFAULT_BOLD);
            textPaint.setColor(ACCENT);
            c.drawText("★ 新纪录 ★", cx, y, textPaint);
        } else {
            textPaint.setColor(TEXT_DIM);
            c.drawText("历史最高分 " + best, cx, y, textPaint);
        }

        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setColor(TEXT_DIM);
        y += smallSize * 1.8f;
        c.drawText("点按板面或下方按钮重新开始", cx, y, textPaint);
    }

    // ---------------------------------------------------------------- 工具

    private static float clamp(float v, float lo, float hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    private static float clamp01(float v) {
        return v < 0f ? 0f : (v > 1f ? 1f : v);
    }
}
