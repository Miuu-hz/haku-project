/* global React */
const { useState } = React;

function Toggle({ on, onChange }) {
  return (
    <span
      role="switch"
      aria-checked={on}
      tabIndex={0}
      className={"toggle" + (on ? " on" : "")}
      onClick={() => onChange(!on)}
      onKeyDown={(e) => { if (e.key === " " || e.key === "Enter") { e.preventDefault(); onChange(!on); } }}
    />
  );
}

function Row({ icon, tone = "", name, desc, right, last, i = 0 }) {
  return (
    <div className="set-row" style={{ ...(last ? { borderBottom: 0 } : null), "--i": i }}>
      <div className={"icon-tile " + tone}>
        <Icon name={icon} size={20} />
      </div>
      <div className="lbl">
        <div className="name">{name}</div>
        {desc ? <div className="desc">{desc}</div> : null}
      </div>
      {right}
    </div>
  );
}

function ProfileCard() {
  return (
    <div className="gcard hero" style={{ marginBottom: 18 }}>
      <span className="accent" style={{ color: "var(--crystal-300)" }} />
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        <CrystalCore size="" />
        <div style={{ flex: 1 }}>
          <p className="haku-eyebrow" style={{ margin: 0 }}>Owner</p>
          <h2 style={{ margin: "2px 0 0", font: "var(--t-h3)" }}>มิว · Miuu</h2>
          <p className="sub" style={{ margin: "4px 0 0", font: "var(--t-caption)", color: "var(--fg-3)" }}>
            ใช้งานมา 38 วัน · 142 บันทึก · เข้ารหัสครบ 100%
          </p>
        </div>
        <button className="chip"><Icon name="edit" size={16} />แก้ไข</button>
      </div>
    </div>
  );
}

function SettingsScreen() {
  const [bio, setBio] = useState(true);
  const [dark, setDark] = useState(true);
  const [notif, setNotif] = useState(true);
  const [shimmer, setShimmer] = useState(true);
  const [cloud, setCloud] = useState(false);

  return (
    <>
      <div className="scr-head">
        <span className="eye">Settings · ตั้งค่า</span>
        <h1 className="ttl">ทุกอย่างของคุณ<br/>อยู่ในเครื่องนี้</h1>
        <p className="sub">Haku ทำงานแบบ on-device — ไม่มีข้อมูลถูกส่งขึ้นคลาวด์</p>
      </div>
      <div className="scr-body">
        <ProfileCard />

        <p className="section-eye">Privacy & lock</p>
        <div className="set-group">
          <Row i={0}
            icon="fingerprint" name="Biometric lock"
            desc="Face ID หรือ ลายนิ้วมือเมื่อเปิดแอพ"
            right={<Toggle on={bio} onChange={setBio} />}
          />
          <Row i={1}
            icon="lock_clock" name="Auto-lock"
            desc="ล็อกอัตโนมัติหลังจากไม่ใช้งาน 1 นาที"
            right={<span style={{ color: "var(--fg-2)", font: "var(--t-body-md)" }}>1 นาที <Icon name="chevron_right" size={20} /></span>}
          />
          <Row i={2}
            icon="shield_lock" tone="lm" name="SQLCipher encryption"
            desc="ฐานข้อมูลทั้งหมดถูกเข้ารหัสด้วย AES-256"
            right={<span className="pill-stat" style={{ background: "rgba(168,255,96,0.14)", color: "var(--vivid-lime)" }}><Icon name="check" size={14} />active</span>}
          />
          <Row i={3}
            icon="cloud_off" name="Cloud sync"
            desc="ปิดอยู่ — ข้อมูลของคุณไม่ออกจากเครื่อง"
            right={<Toggle on={cloud} onChange={setCloud} />}
          />
        </div>

        <p className="section-eye">AI · LLM Provider</p>
        <div className="set-group">
          <Row
            icon="memory" name="On-device · Gemma 3 1B"
            desc="MediaPipe Tasks GenAI · พร้อมใช้งาน"
            right={<span className="pill-stat"><Icon name="check" size={14} />active</span>}
          />
          <Row
            icon="cloud" tone="lv" name="Cloud fallback"
            desc="ใช้เมื่อ on-device ไม่พอ — ปัจจุบัน: ปิด"
            right={<Icon name="chevron_right" size={20} />}
          />
          <Row
            icon="key" tone="cr" name="API keys"
            desc="Gemini · Claude · OpenAI · OpenRouter"
            right={<Icon name="chevron_right" size={20} />}
          />
        </div>

        <p className="section-eye">Appearance</p>
        <div className="set-group">
          <Row
            icon="dark_mode" tone="lv" name="Dark mode"
            desc="พื้นหลัง Aurora ตลอดเวลา"
            right={<Toggle on={dark} onChange={setDark} />}
          />
          <Row
            icon="auto_awesome" name="Crystal shimmer"
            desc="แอนิเมชันแสงเคลื่อนผ่านการ์ดกระจก"
            right={<Toggle on={shimmer} onChange={setShimmer} />}
          />
          <Row
            icon="palette" tone="lv" name="Accent color"
            right={
              <div style={{ display: "flex", gap: 6 }}>
                <span style={{ width: 22, height: 22, borderRadius: 999, background: "var(--crystal-400)", boxShadow: "var(--glow-cyan)" }}></span>
                <span style={{ width: 22, height: 22, borderRadius: 999, background: "var(--lavender-400)", opacity: .5 }}></span>
                <span style={{ width: 22, height: 22, borderRadius: 999, background: "var(--vivid-magenta)", opacity: .5 }}></span>
              </div>
            }
          />
        </div>

        <p className="section-eye">Data</p>
        <div className="set-group">
          <Row icon="ios_share" name="ส่งออกข้อมูล"
            desc="JSON · Markdown · CSV · backup"
            right={<Icon name="chevron_right" size={20} />}
          />
          <Row icon="notifications" tone="cr" name="Notifications"
            desc="Morning agenda · Evening summary"
            right={<Toggle on={notif} onChange={setNotif} />}
          />
          <Row icon="delete_forever" tone="cr" name="ลบบันทึกทั้งหมด"
            desc="ไม่สามารถย้อนกลับได้"
            right={<Icon name="chevron_right" size={20} />}
          />
        </div>

        <p style={{ textAlign: "center", color: "var(--fg-3)", font: "var(--t-mono-sm)", marginTop: 26 }}>
          Haku 箱 · v0.1.0 · made with care for privacy
        </p>
      </div>
    </>
  );
}

Object.assign(window, { SettingsScreen });
