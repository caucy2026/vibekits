package com.vibekits.whacdemo;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
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
 * 原生 Android 打地鼠（Whac-A-Mole）主界面。
 *
 * 功能：
 * - 九宫格（3x3）地鼠，随机冒头 / 缩回，带冒头动画
 * - 60 秒倒计时，实时计分，命中 / 漏掉统计，最高分本地保存
 * - 开始 与 重玩 按钮，整格放大触摸目标，适合手指点击
 * - 强制横屏（见 AndroidManifest.xml 的 screenOrientation="landscape"）
 *
 * 实现约束：只使用 Android framework API（自绘 Canvas），不依赖 AndroidX，
 * 因此可以在任意 Android SDK + aapt2 + javac/d8 + apksigner 环境下编译。
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

/** 自绘游戏视图：绘制、计时、命中判定都在这里完成。 */
class GameView extends View {

    private enum State { READY, RUNNING, OVER }

    private static final int HOLES = 9;                  // 3 x 3 九宫格
    private static final long GAME_MS = 60000L;          // 60 秒倒计时
    private static final long POP_MS = 150L;             // 冒头 / 缩回动画时长
    private static final long LIFE_MIN_MS = 520L;        // 地鼠停留时间（下界）
    private static final long LIFE_MAX_MS = 1000L;       // 地鼠停留时间（上界）
    private static final long GAP_MIN_MS = 260L;         // 两只地鼠之间的间隔（下界）
    private static final long GAP_MAX_MS = 620L;         // 两只地鼠之间的间隔（上界）
    private static final long FIRST_MOLE_MS = 380L;      // 开局第一只地鼠的延迟
    private static final long RESTART_GUARD_MS = 700L;   // 结束后防止误触立即重开
    private static final int HIT_SCORE = 10;             // 每命中一只得分

    private final Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint linePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private final RectF[] cells = new RectF[HOLES];
    private final RectF[] holeOvals = new RectF[HOLES];
    private final RectF button = new RectF();
    private final RectF boardRect = new RectF();

    private final Random random = new Random();
    private final SharedPreferences prefs;

    private State state = State.READY;

    private int score = 0;
    private int best = 0;
    private int hits = 0;
    private int misses = 0;

    private int moleIndex = -1;
    private long moleRiseAt = 0L;
    private long moleSinkAt = 0L;
    private long nextMoleAt = 0L;
    private float pop = 0f;

    private long timeLeftMs = GAME_MS;
    private long lastFrameAt = 0L;
    private long overAt = 0L;

    private int flashIndex = -1;
    private long flashAt = 0L;
    private static final long IMPACT_MS = 1400L;
    private long impactAt = 0L;
    private float impactX = 0f;
    private float impactY = 0f;
    private float impactRadius = 0f;
    private int impactCell = -1;
    private boolean impactHit = false;
    private float impactPop = 0f;

    private float viewW = 0f;
    private float viewH = 0f;
    private float pad = 12f;
    private float headerH = 64f;
    private Shader bgShader = null;

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
        textPaint.setTypeface(Typeface.DEFAULT_BOLD);
        textPaint.setTextAlign(Paint.Align.CENTER);
        linePaint.setStyle(Paint.Style.STROKE);
        linePaint.setStrokeCap(Paint.Cap.ROUND);
    }

    void onShown() {
        lastFrameAt = 0L;
        invalidate();
    }

    void onHidden() {
        lastFrameAt = 0L;
    }

    // ------------------------------------------------------------------ 布局

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        layout(w, h);
    }

    private void layout(int w, int h) {
        viewW = w;
        viewH = h;
        pad = Math.max(Math.min(w, h) * 0.03f, 10f);
        headerH = Math.max(h * 0.17f, 56f);
        boardRect.set(pad, pad + headerH, w - pad, h - pad);

        float cellW = boardRect.width() / 3f;
        float cellH = boardRect.height() / 3f;
        float gapX = cellW * 0.055f;
        float gapY = cellH * 0.06f;
        for (int r = 0; r < 3; r++) {
            for (int c = 0; c < 3; c++) {
                int i = r * 3 + c;
                cells[i].set(boardRect.left + c * cellW + gapX,
                        boardRect.top + r * cellH + gapY,
                        boardRect.left + (c + 1) * cellW - gapX,
                        boardRect.top + (r + 1) * cellH - gapY);

                float ow = cells[i].width() * 0.86f;
                float oh = cells[i].height() * 0.46f;
                float cx = cells[i].centerX();
                float cy = cells[i].bottom - cells[i].height() * 0.26f;
                holeOvals[i].set(cx - ow * 0.5f, cy - oh * 0.5f, cx + ow * 0.5f, cy + oh * 0.5f);
            }
        }

        float bw = Math.min(w * 0.38f, 660f);
        float bh = Math.max(h * 0.17f, 88f);
        float bcx = w * 0.5f;
        float bcy = boardRect.centerY() + boardRect.height() * 0.13f;
        button.set(bcx - bw * 0.5f, bcy - bh * 0.5f, bcx + bw * 0.5f, bcy + bh * 0.5f);

        bgShader = new LinearGradient(0f, 0f, 0f, h, 0xFF0B2E16, 0xFF1B5E20, Shader.TileMode.CLAMP);
    }

    // ------------------------------------------------------------------ 主循环

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
        if (flashIndex >= 0 && now - flashAt > 260L) {
            flashIndex = -1;
        }
        if (impactAt > 0L && now - impactAt >= IMPACT_MS) {
            impactAt = 0L;
            impactCell = -1;
        }

        drawBackground(canvas);
        drawHud(canvas);
        drawBoard(canvas);
        if (state == State.READY) {
            drawReadyOverlay(canvas);
        } else if (state == State.OVER) {
            drawOverOverlay(canvas);
        }

        if (state == State.RUNNING || impactAt > 0L) {
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
            nextMoleAt = now + GAP_MIN_MS + (long) (random.nextDouble() * (GAP_MAX_MS - GAP_MIN_MS));
        }
    }

    private void spawnMole(long now) {
        int idx;
        do {
            idx = random.nextInt(HOLES);
        } while (idx == moleIndex);
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
        timeLeftMs = GAME_MS;
        moleIndex = -1;
        pop = 0f;
        flashIndex = -1;
        impactAt = 0L;
        impactCell = -1;
        nextMoleAt = now + FIRST_MOLE_MS;
        lastFrameAt = 0L;
        invalidate();
    }

    private void finishGame(long now) {
        state = State.OVER;
        overAt = now;
        moleIndex = -1;
        pop = 0f;
        if (score > best) {
            best = score;
            prefs.edit().putInt("best_score", best).apply();
        }
    }

    // ------------------------------------------------------------------ 触摸

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            long now = SystemClock.uptimeMillis();
            if (state == State.READY) {
                startGame(now);
            } else if (state == State.OVER) {
                if (now - overAt >= RESTART_GUARD_MS) {
                    startGame(now);
                }
            } else {
                whack(event.getX(), event.getY(), now);
            }
        }
        return true;
    }

    private void whack(float x, float y, long now) {
        boolean hit = moleIndex >= 0 && pop >= 0.30f && cells[moleIndex].contains(x, y);
        impactAt = now;
        impactHit = hit;
        impactCell = hit ? moleIndex : cellAt(x, y);
        impactPop = pop;
        if (hit) {
            RectF oval = holeOvals[moleIndex];
            float r = Math.min(cells[moleIndex].width() * 0.26f,
                    cells[moleIndex].height() * 0.42f);
            impactX = oval.centerX();
            impactY = oval.centerY() + r * 0.95f - r * 1.70f * pop;
            impactRadius = r;
        } else {
            impactX = x;
            impactY = y;
            impactRadius = Math.min(viewW, viewH) * 0.065f;
        }
        invalidate();
        if (!hit) return;
        score += HIT_SCORE;
        hits++;
        flashIndex = moleIndex;
        flashAt = now;
        moleIndex = -1;
        pop = 0f;
        nextMoleAt = now + GAP_MIN_MS + (long) (random.nextDouble() * (GAP_MAX_MS - GAP_MIN_MS));
    }

    private int cellAt(float x, float y) {
        for (int i = 0; i < HOLES; i++) {
            if (cells[i].contains(x, y)) return i;
        }
        return -1;
    }

    // ------------------------------------------------------------------ 绘制

    private void drawBackground(Canvas c) {
        fillPaint.setStyle(Paint.Style.FILL);
        fillPaint.setShader(bgShader);
        c.drawRect(0f, 0f, viewW, viewH, fillPaint);
        fillPaint.setShader(null);

        fillPaint.setColor(0xFF2E7D32);
        c.drawRoundRect(boardRect, 20f, 20f, fillPaint);
    }

    private void drawHud(Canvas c) {
        float labelSize = Math.max(viewH * 0.042f, 17f);
        float valueSize = Math.max(viewH * 0.075f, 28f);
        float labelBaseline = pad + labelSize * 1.25f;
        float valueBaseline = pad + headerH - Math.max(4f, viewH * 0.012f);

        textPaint.setTextAlign(Paint.Align.LEFT);
        textPaint.setTextSize(labelSize);
        textPaint.setColor(0xFFA5D6A7);
        c.drawText("得分", pad + 8f, labelBaseline, textPaint);
        textPaint.setTextSize(valueSize);
        textPaint.setColor(Color.WHITE);
        c.drawText(String.valueOf(score), pad + 8f, valueBaseline, textPaint);

        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTextSize(labelSize);
        textPaint.setColor(0xFFA5D6A7);
        c.drawText("倒计时", viewW * 0.5f, labelBaseline, textPaint);
        int secs = (int) ((timeLeftMs + 999L) / 1000L);
        textPaint.setTextSize(valueSize * 1.15f);
        textPaint.setColor(secs <= 10 ? 0xFFFF5252 : 0xFFFFD54F);
        c.drawText(secs + " 秒", viewW * 0.5f, valueBaseline, textPaint);

        textPaint.setTextAlign(Paint.Align.RIGHT);
        textPaint.setTextSize(labelSize);
        textPaint.setColor(0xFFA5D6A7);
        c.drawText("最高分", viewW - pad - 8f, labelBaseline, textPaint);
        textPaint.setTextSize(valueSize);
        textPaint.setColor(Color.WHITE);
        c.drawText(String.valueOf(best), viewW - pad - 8f, valueBaseline, textPaint);

        textPaint.setTextAlign(Paint.Align.CENTER);
    }

    private void drawBoard(Canvas c) {
        fillPaint.setStyle(Paint.Style.FILL);
        for (int i = 0; i < HOLES; i++) {
            RectF oval = holeOvals[i];
            RectF mound = new RectF(oval);
            mound.inset(-oval.width() * 0.03f, -oval.height() * 0.26f);
            fillPaint.setColor(0xFF6D4C41);
            c.drawOval(mound, fillPaint);

            fillPaint.setColor(0xFF241610);
            c.drawOval(oval, fillPaint);
        }

        if (moleIndex >= 0 && pop > 0.01f) {
            drawMole(c, moleIndex, pop);
        }

        // 洞口前沿盖住地鼠下半身，形成“从洞里冒出来”的效果
        for (int i = 0; i < HOLES; i++) {
            RectF oval = holeOvals[i];
            c.save();
            c.clipRect(cells[i].left - 2f, oval.centerY(), cells[i].right + 2f, cells[i].bottom + 4f);
            fillPaint.setColor(0xFF3B2418);
            c.drawOval(oval, fillPaint);
            c.restore();
        }

        if (flashIndex >= 0) {
            RectF oval = holeOvals[flashIndex];
            long age = SystemClock.uptimeMillis() - flashAt;
            float k = clamp01(1f - age / 260f);
            linePaint.setStrokeWidth(Math.max(3f, oval.height() * 0.18f));
            linePaint.setColor(Color.argb((int) (200 * k), 0x69, 0xF0, 0xAE));
            RectF ring = new RectF(oval);
            ring.inset(-oval.width() * 0.04f, -oval.height() * 0.20f);
            c.drawOval(ring, linePaint);
        }
        drawImpact(c, SystemClock.uptimeMillis());
    }

    private void drawImpact(Canvas c, long now) {
        if (impactAt == 0L) return;
        float age = Math.max(0f, now - impactAt);
        float r = impactRadius;
        float x = impactX;
        float y = impactY;

        if (impactHit && impactCell >= 0 && age < 350f) {
            float squash = 1f - 0.55f * clamp01(age / 350f);
            c.save();
            c.scale(1f + (1f - squash) * 0.18f, squash, x, y);
            drawMole(c, impactCell, Math.max(0.32f, impactPop * squash));
            c.restore();
        }

        // Short hammer swing: its head lands at the mole's computed head
        // position, even when the touch is elsewhere inside the generous cell.
        if (age < 520f) {
            float strike = clamp01(age / 130f);
            float vanish = 1f - clamp01((age - 320f) / 200f);
            int alpha = (int) (255f * vanish);
            c.save();
            c.translate(x + r * 0.55f * (1f - strike),
                    y - r * 0.75f * (1f - strike));
            c.rotate(-34f * (1f - strike));
            linePaint.setStrokeWidth(Math.max(6f, r * 0.19f));
            linePaint.setColor(Color.argb(alpha, 0x70, 0x43, 0x24));
            c.drawLine(r * 0.27f, -r * 0.20f,
                    r * 1.15f, -r * 1.08f, linePaint);
            fillPaint.setColor(Color.argb(alpha, 0xC8, 0xDA, 0xE1));
            RectF head = new RectF(-r * 0.58f, -r * 0.39f,
                    r * 0.46f, r * 0.17f);
            c.drawRoundRect(head, r * 0.12f, r * 0.12f, fillPaint);
            linePaint.setStrokeWidth(Math.max(2f, r * 0.05f));
            linePaint.setColor(Color.argb(alpha, 0x54, 0x66, 0x6D));
            c.drawRoundRect(head, r * 0.12f, r * 0.12f, linePaint);
            c.restore();
        }

        // Local glass-like fractures expand on contact, then draw back toward
        // the impact point while fading. No random per-frame values: no flicker.
        if (age < 120f || age >= IMPACT_MS) return;
        float recover = clamp01((age - 430f) / (IMPACT_MS - 430f));
        float extent = 1f - recover * 0.82f;
        float opacity = (1f - recover) * (impactHit ? 1f : 0.52f);
        int alpha = (int) (220f * opacity);
        c.save();
        if (impactCell >= 0) c.clipRect(cells[impactCell]);
        linePaint.setColor(Color.argb(alpha, 0xE5, 0xF7, 0xFF));
        linePaint.setStrokeWidth(Math.max(2f, r * 0.045f) * (1f - recover * 0.35f));
        for (int i = 0; i < 8; i++) {
            double angle = i * Math.PI / 4.0 - 0.18;
            float dx = (float) Math.cos(angle);
            float dy = (float) Math.sin(angle);
            float sideX = -dy;
            float sideY = dx;
            float end = r * (0.74f + (i % 3) * 0.17f) * extent;
            Path crack = new Path();
            crack.moveTo(x, y);
            crack.lineTo(x + dx * end * 0.32f + sideX * r * 0.10f,
                    y + dy * end * 0.32f + sideY * r * 0.10f);
            crack.lineTo(x + dx * end * 0.68f - sideX * r * 0.07f,
                    y + dy * end * 0.68f - sideY * r * 0.07f);
            crack.lineTo(x + dx * end, y + dy * end);
            c.drawPath(crack, linePaint);
            if (i % 2 == 0) {
                c.drawLine(x + dx * end * 0.68f - sideX * r * 0.07f,
                        y + dy * end * 0.68f - sideY * r * 0.07f,
                        x + dx * end * 0.73f + sideX * r * 0.21f,
                        y + dy * end * 0.73f + sideY * r * 0.21f, linePaint);
            }
        }
        fillPaint.setColor(Color.argb((int) (95f * opacity), 0xFF, 0xFF, 0xFF));
        c.drawCircle(x, y, Math.max(3f, r * 0.11f * extent), fillPaint);
        c.restore();
    }

    private void drawMole(Canvas c, int index, float popValue) {
        RectF cell = cells[index];
        RectF oval = holeOvals[index];
        float cx = oval.centerX();
        float holeCy = oval.centerY();
        float r = Math.min(cell.width() * 0.26f, cell.height() * 0.42f);
        float lowY = holeCy + r * 0.95f;
        float highY = holeCy - r * 0.75f;
        float cy = lowY + (highY - lowY) * popValue;

        c.save();
        c.clipRect(cell.left - 2f, cell.top - 2f, cell.right + 2f, holeCy + 1f);

        // 耳朵
        fillPaint.setColor(0xFF6D4C41);
        c.drawCircle(cx - r * 0.74f, cy - r * 0.60f, r * 0.27f, fillPaint);
        c.drawCircle(cx + r * 0.74f, cy - r * 0.60f, r * 0.27f, fillPaint);

        // 身体
        fillPaint.setColor(0xFF8D6E63);
        c.drawCircle(cx, cy, r, fillPaint);

        // 肚皮
        fillPaint.setColor(0xFFD7CCC8);
        c.drawCircle(cx, cy + r * 0.44f, r * 0.56f, fillPaint);

        if (popValue > 0.35f) {
            // 眼睛
            float ey = cy - r * 0.18f;
            float ex = r * 0.34f;
            fillPaint.setColor(Color.WHITE);
            c.drawCircle(cx - ex, ey, r * 0.21f, fillPaint);
            c.drawCircle(cx + ex, ey, r * 0.21f, fillPaint);
            fillPaint.setColor(0xFF1A1A1A);
            c.drawCircle(cx - ex, ey, r * 0.10f, fillPaint);
            c.drawCircle(cx + ex, ey, r * 0.10f, fillPaint);

            // 鼻子
            fillPaint.setColor(0xFFFF8A80);
            c.drawCircle(cx, cy + r * 0.20f, r * 0.14f, fillPaint);

            // 胡须
            linePaint.setStrokeWidth(Math.max(1.6f, r * 0.07f));
            linePaint.setColor(0xFF4E342E);
            c.drawLine(cx - r * 0.22f, cy + r * 0.30f, cx - r * 0.95f, cy + r * 0.14f, linePaint);
            c.drawLine(cx - r * 0.22f, cy + r * 0.40f, cx - r * 0.95f, cy + r * 0.48f, linePaint);
            c.drawLine(cx + r * 0.22f, cy + r * 0.30f, cx + r * 0.95f, cy + r * 0.14f, linePaint);
            c.drawLine(cx + r * 0.22f, cy + r * 0.40f, cx + r * 0.95f, cy + r * 0.48f, linePaint);
        }
        c.restore();
    }

    private void drawReadyOverlay(Canvas c) {
        fillPaint.setStyle(Paint.Style.FILL);
        fillPaint.setColor(0xD0000000);
        c.drawRect(0f, 0f, viewW, viewH, fillPaint);

        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setColor(Color.WHITE);
        textPaint.setTextSize(Math.max(viewH * 0.115f, 42f));
        c.drawText("打 地 鼠", viewW * 0.5f, viewH * 0.30f, textPaint);

        textPaint.setTextSize(Math.max(viewH * 0.055f, 21f));
        textPaint.setColor(0xFFB2DFB6);
        c.drawText("60 秒倒计时 · 九宫格地鼠 · 每只 " + HIT_SCORE + " 分",
                viewW * 0.5f, viewH * 0.30f + Math.max(viewH * 0.115f, 44f), textPaint);

        drawButton(c, "开始游戏");

        textPaint.setTextSize(Math.max(viewH * 0.045f, 17f));
        textPaint.setColor(0xFF9E9E9E);
        c.drawText("点击屏幕任意位置即可开始", viewW * 0.5f,
                Math.min(button.bottom + Math.max(viewH * 0.10f, 40f), viewH - pad), textPaint);
    }

    private void drawOverOverlay(Canvas c) {
        fillPaint.setStyle(Paint.Style.FILL);
        fillPaint.setColor(0xD9000000);
        c.drawRect(0f, 0f, viewW, viewH, fillPaint);

        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setColor(Color.WHITE);
        float titleSize = Math.max(viewH * 0.105f, 38f);
        textPaint.setTextSize(titleSize);
        c.drawText("时间到！", viewW * 0.5f, viewH * 0.27f, textPaint);

        textPaint.setTextSize(Math.max(viewH * 0.085f, 30f));
        textPaint.setColor(0xFFFFD54F);
        c.drawText("得分 " + score, viewW * 0.5f, viewH * 0.27f + titleSize * 0.95f, textPaint);

        textPaint.setTextSize(Math.max(viewH * 0.048f, 18f));
        textPaint.setColor(0xFFC8E6C9);
        c.drawText("命中 " + hits + " 只 · 漏掉 " + misses + " 只 · 最高分 " + best,
                viewW * 0.5f, viewH * 0.27f + titleSize * 0.95f + Math.max(viewH * 0.10f, 36f), textPaint);

        drawButton(c, "重新开始");
    }

    private void drawButton(Canvas c, String label) {
        float radius = button.height() * 0.24f;
        fillPaint.setStyle(Paint.Style.FILL);
        fillPaint.setColor(0xFFFFB300);
        c.drawRoundRect(button, radius, radius, fillPaint);

        linePaint.setStrokeWidth(Math.max(3f, button.height() * 0.05f));
        linePaint.setColor(0xFF7A4B00);
        c.drawRoundRect(button, radius, radius, linePaint);

        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setColor(0xFF2B1B12);
        textPaint.setTextSize(button.height() * 0.42f);
        float baseline = button.centerY() - (textPaint.descent() + textPaint.ascent()) * 0.5f;
        c.drawText(label, button.centerX(), baseline, textPaint);
    }

    private static float clamp01(float v) {
        return v < 0f ? 0f : (v > 1f ? 1f : v);
    }
}
