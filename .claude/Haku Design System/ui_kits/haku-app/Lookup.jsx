/* global React */
const { useState, useEffect, useRef } = React;

/* ============================================================
   Haku Crystal — UI kit components
   3 screens: Lookup (Now-Brief), Chat, Settings
   ============================================================ */

/* -------------------- Common atoms -------------------- */
function Icon({ name, filled, size = 22, color, weight }) {
  return (
    <span
      className="material-icons-round"
      style={{
        fontFamily: '"Material Icons Round"',
        fontWeight: "normal",
        fontStyle: "normal",
        lineHeight: 1,
        letterSpacing: "normal",
        textTransform: "none",
        whiteSpace: "nowrap",
        wordWrap: "normal",
        direction: "ltr",
        WebkitFontFeatureSettings: '"liga"',
        fontFeatureSettings: '"liga"',
        WebkitFontSmoothing: "antialiased",
        fontSize: size,
        color,
        display: "inline-block",
      }}
    >
      {name}
    </span>
  );
}

function PillStat({ icon, children }) {
  return (
    <span className="pill-stat">
      {icon ? <Icon name={icon} size={14} /> : null}
      {children}
    </span>
  );
}

function CrystalCore({ size = "" }) {
  return (
    <div className={"core " + size} aria-hidden="true">
      <span className="core-spark" />
      <span className="core-spark s2" />
    </div>
  );
}

/* -------------------- Bottom nav -------------------- */
function BottomNav({ active, onChange }) {
  const tabs = [
    { id: "lookup", icon: "grid_view", label: "Lookup" },
    { id: "chat",   icon: "forum",     label: "Chat" },
    { id: "set",    icon: "tune",      label: "Settings" },
  ];
  return (
    <nav className="btm-nav" role="tablist">
      {tabs.map(t => (
        <button
          key={t.id}
          role="tab"
          aria-selected={active === t.id}
          className={"tab" + (active === t.id ? " active" : "")}
          onClick={() => onChange(t.id)}
        >
          <Icon name={t.icon} filled={active === t.id} size={20} />
          <span>{t.label}</span>
        </button>
      ))}
    </nav>
  );
}

/* -------------------- Lookup screen -------------------- */
function LookupHero() {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(id);
  }, []);
  const time = now.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
  return (
    <div className="lookup-hero">
      <CrystalCore size="lg" />
      <div style={{ flex: 1, minWidth: 0 }}>
        <p className="haku-eyebrow" style={{ margin: 0 }}>Wednesday · 8 May</p>
        <h2 style={{
          margin: "4px 0 6px",
          font: "var(--t-h1)",
          fontSize: 30,
          letterSpacing: "var(--letter-display)",
          color: "var(--fg-1)",
        }}>สวัสดีตอนเช้า, มิว</h2>
        <p className="brief-line">
          วันนี้คุณมี <span className="hl">2 นัดหมาย</span> และอากาศ <span className="hl">28°</span> ฝนเล็กน้อย
        </p>
        <div style={{ display: "flex", gap: 6, marginTop: 12 }}>
          <PillStat icon="auto_awesome">3 คำแนะนำใหม่</PillStat>
          <PillStat icon="memory">on-device</PillStat>
        </div>
      </div>
    </div>
  );
}

function ChipsRow() {
  const items = [
    { i: "edit_note",   l: "เขียนบันทึกวันนี้" },
    { i: "event",       l: "ดูปฏิทิน" },
    { i: "graphic_eq",  l: "สรุปอารมณ์สัปดาห์" },
    { i: "place",       l: "ที่ที่ไปบ่อย" },
    { i: "shield_lock", l: "Privacy" },
  ];
  return (
    <div className="chips" role="list">
      {items.map((c, i) => (
        <button key={i} className="chip" role="listitem">
          <Icon name={c.i} size={16} />{c.l}
        </button>
      ))}
    </div>
  );
}

function CalendarCard() {
  return (
    <div className="gcard lm tap" style={{ "--i": 1 }}>
      <span className="accent" />
      <p className="eye"><Icon name="event" size={14} />Calendar · ถัดไป</p>
      <h4>Daily standup</h4>
      <p className="sub">10:00 – 10:30 · Google Meet</p>
      <div className="avatar-row" style={{ marginTop: 12 }}>
        <span className="av cy"></span>
        <span className="av"></span>
        <span className="av gd"></span>
        <span className="av cr"></span>
        <span className="av" style={{ background: "rgba(80,90,140,0.10)", display: "grid", placeItems: "center", color: "var(--fg-2)", font: "10px var(--font-sans)" }}>+2</span>
      </div>
    </div>
  );
}

function WeatherCard() {
  return (
    <div className="gcard gd tap" style={{ "--i": 2 }}>
      <span className="accent" />
      <p className="eye"><Icon name="rainy" size={14} />Weather</p>
      <p className="num" style={{ fontSize: 38, marginTop: 4 }}>28°</p>
      <p className="sub">ฝนเล็กน้อย · กรุงเทพฯ</p>
      <div style={{ display: "flex", gap: 8, marginTop: 10, color: "var(--fg-3)", font: "var(--t-caption)" }}>
        <span>10:00 · 27°</span><span>·</span><span>14:00 · 31°</span>
      </div>
    </div>
  );
}

function MoodCard() {
  return (
    <div className="gcard lv span2 tap" style={{ "--i": 3 }}>
      <span className="accent" />
      <p className="eye"><Icon name="favorite" size={14} />Mood · 7 วัน</p>
      <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
        <span style={{ font: "var(--t-h2)", color: "var(--fg-1)" }}>ดี</span>
        <span style={{ font: "var(--t-caption)", color: "var(--vivid-mint)" }}>↗ ขึ้น 12% จากสัปดาห์ก่อน</span>
      </div>
      <div className="mood-row">
        <span className="mood-pip mid"   style={{ height: 14 }}></span>
        <span className="mood-pip"        style={{ height: 18 }}></span>
        <span className="mood-pip high"   style={{ height: 22 }}></span>
        <span className="mood-pip mid"    style={{ height: 18 }}></span>
        <span className="mood-pip high"   style={{ height: 26 }}></span>
        <span className="mood-pip"        style={{ height: 16 }}></span>
        <span className="mood-pip high"   style={{ height: 28 }}></span>
      </div>
    </div>
  );
}

function SuggestionCard() {
  return (
    <div className="gcard cy span2" style={{ "--i": 4, background: "linear-gradient(160deg, rgba(140,225,255,0.55) 0%, rgba(255,255,255,0.78) 50%, rgba(220,205,250,0.55) 100%)" }}>
      <span className="accent" />
      <p className="eye" style={{ color: "var(--crystal-300)" }}>
        <Icon name="auto_awesome" filled size={14} />Haku แนะนำ
      </p>
      <p className="brief-line" style={{ marginTop: 4 }}>
        เมื่อวานคุณนอนช้า ลองเลื่อนนัด <span className="hl">บ่ายโมง</span> ออกไป 30 นาทีไหม?
      </p>
      <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
        <button className="chip" style={{ background: "linear-gradient(180deg,#7BEBFF,var(--crystal-400))", color: "var(--fg-on-cyan)", boxShadow: "var(--glow-cyan)" }}>
          <Icon name="check" size={16} color="var(--fg-on-cyan)" />ทำเลย
        </button>
        <button className="chip">ภายหลัง</button>
        <button className="chip" style={{ marginLeft: "auto" }}><Icon name="more_horiz" size={16} /></button>
      </div>
    </div>
  );
}

function LocationCard() {
  return (
    <div className="gcard cr tap" style={{ "--i": 5 }}>
      <span className="accent" />
      <p className="eye"><Icon name="place" size={14} />Where</p>
      <h4 style={{ marginTop: 2 }}>กลับถึงบ้าน</h4>
      <p className="sub">19:24 · 18 นาทีที่แล้ว</p>
      <div className="spark">
        {[8, 14, 10, 18, 22, 16, 24, 20, 28, 18, 22, 26].map((h, i) => (
          <span key={i} style={{ height: h }}></span>
        ))}
      </div>
    </div>
  );
}

function HealthCard() {
  return (
    <div className="gcard mt tap" style={{ "--i": 6 }}>
      <span className="accent" />
      <p className="eye"><Icon name="ecg_heart" size={14} />Health · พรุ่งนี้</p>
      <h4 style={{ marginTop: 2 }}>กินยาวิตามินดี</h4>
      <p className="sub">07:30 · เตือนซ้ำทุกวัน</p>
      <div style={{ display: "flex", gap: 6, marginTop: 12 }}>
        <span className="pill-stat" style={{ background: "rgba(95,255,199,0.12)", color: "var(--vivid-mint)" }}>
          <Icon name="check" size={14} />4/4 วันนี้
        </span>
      </div>
    </div>
  );
}

function JournalCard() {
  return (
    <div className="gcard mg tap span2" style={{ "--i": 7 }}>
      <span className="accent" />
      <p className="eye"><Icon name="auto_stories" size={14} />Journal · ล่าสุด</p>
      <p className="body" style={{ color: "var(--fg-1)", font: "var(--t-body-md)", marginTop: 2 }}>
        "วันนี้กินกาแฟร้านเดิมที่ทองหล่อ คุยกับนุ่นนานหน่อย รู้สึกดีกว่าที่คิด"
      </p>
      <div style={{ display: "flex", gap: 10, marginTop: 12, alignItems: "center" }}>
        <span className="haku-eyebrow">เมื่อวาน · 21:14</span>
        <span style={{ flex: 1 }}></span>
        <button className="chip" style={{ padding: "6px 10px" }}>
          <Icon name="edit_note" size={14} />เขียนต่อ
        </button>
      </div>
    </div>
  );
}

function LookupScreen() {
  return (
    <div className="scr-body">
      <LookupHero />
      <ChipsRow />
      <div className="masonry stagger pop-cascade">
        <SuggestionCard />
        <CalendarCard />
        <WeatherCard />
        <MoodCard />
        <LocationCard />
        <HealthCard />
        <JournalCard />
      </div>
    </div>
  );
}

Object.assign(window, { LookupScreen, BottomNav, Icon, CrystalCore });
