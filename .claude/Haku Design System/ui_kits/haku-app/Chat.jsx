/* global React */
const { useState, useEffect, useRef } = React;

/* ============================================================
   Chat screen — Haku AI thread
   ============================================================ */

function ThinkingBubble() {
  return (
    <div className="bubble ai" style={{ padding: "14px 16px" }}>
      <div className="thinking">
        <span className="dot"></span>
        <span className="dot"></span>
        <span className="dot"></span>
      </div>
    </div>
  );
}

function Bubble({ from, text, time }) {
  return (
    <div className={"bubble " + from}>
      <div>{text}</div>
      {time ? <div className="meta">{time}</div> : null}
    </div>
  );
}

const SEED_THREAD = [
  { from: "ai", text: "สวัสดีตอนเช้าค่ะ มีอะไรให้ Haku ช่วยมั้ย?", time: "08:14" },
  { from: "me", text: "ช่วยสรุปสัปดาห์ที่ผ่านมาให้หน่อย", time: "08:15" },
  { from: "ai", text: "ดูจาก 7 วันที่ผ่านมา คุณเขียนบันทึก 5 ครั้ง ส่วนใหญ่เป็นช่วงเย็น อารมณ์โดยรวมดีกว่าสัปดาห์ก่อน 12% และไปร้านกาแฟที่ทองหล่อ 3 ครั้ง 🙂", time: "08:15" },
  { from: "me", text: "ขอบใจ เดี๋ยวนัดประชุมตอน 3 โมงนะ", time: "08:16" },
  { from: "ai", text: "เพิ่มเข้าปฏิทินแล้วค่ะ 'ประชุม' 15:00–16:00 พร้อมเตือนล่วงหน้า 15 นาที", time: "08:16" },
];

function HakuChip({ children }) {
  return (
    <span style={{
      display: "inline-flex",
      alignItems: "center",
      gap: 4,
      padding: "2px 8px",
      borderRadius: 999,
      background: "rgba(60,223,255,0.18)",
      color: "var(--crystal-200)",
      font: "var(--t-caption)",
      fontWeight: 600,
      marginRight: 6,
    }}>
      <span className="msr msr--filled" style={{ fontSize: 12 }}>auto_awesome</span>
      {children}
    </span>
  );
}

function EventConfirmation() {
  return (
    <div className="gcard cy" style={{ marginTop: 8, alignSelf: "flex-start", maxWidth: "86%" }}>
      <span className="accent" />
      <p className="eye"><Icon name="event_available" size={14} />เพิ่มเข้าปฏิทิน</p>
      <h4 style={{ marginTop: 2 }}>ประชุม</h4>
      <p className="sub">วันนี้ · 15:00 – 16:00 · เตือน 15 นาที</p>
      <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
        <button className="chip" style={{ background: "linear-gradient(180deg,#7BEBFF,var(--crystal-400))", color: "var(--fg-on-cyan)", boxShadow: "var(--glow-cyan)" }}>
          <Icon name="check" size={16} color="var(--fg-on-cyan)" />ตกลง
        </button>
        <button className="chip"><Icon name="edit" size={16} />แก้ไข</button>
      </div>
    </div>
  );
}

function ChatHeader() {
  return (
    <div className="scr-head">
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <CrystalCore size="sm" />
        <div>
          <p className="eye" style={{ font: "var(--t-eyebrow)", letterSpacing: "var(--letter-eyebrow)", textTransform: "uppercase", color: "var(--crystal-300)", margin: 0 }}>
            <HakuChip>on-device · Gemma 3</HakuChip>
          </p>
          <h1 className="ttl" style={{ fontSize: 26, marginTop: 4 }}>Haku AI</h1>
        </div>
      </div>
    </div>
  );
}

function ChatScreen() {
  const [thread, setThread] = useState(SEED_THREAD);
  const [draft, setDraft] = useState("");
  const [thinking, setThinking] = useState(false);
  const scrollRef = useRef(null);

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [thread, thinking]);

  const send = () => {
    const text = draft.trim();
    if (!text) return;
    const time = new Date().toLocaleTimeString("th-TH", { hour: "2-digit", minute: "2-digit" });
    setThread(t => [...t, { from: "me", text, time }]);
    setDraft("");
    setThinking(true);
    setTimeout(() => {
      setThinking(false);
      setThread(t => [...t, {
        from: "ai",
        text: "รับทราบค่ะ Haku จดไว้ในบันทึกแบบเข้ารหัสบนเครื่องนี้แล้ว ไม่มีข้อมูลถูกส่งขึ้นคลาวด์",
        time,
      }]);
    }, 1200);
  };

  return (
    <>
      <ChatHeader />
      <div className="scr-body" ref={scrollRef} style={{ padding: "0 18px 160px" }}>
        <div className="chat-stream">
          {thread.map((m, i) => (
            <React.Fragment key={i}>
              <Bubble {...m} />
              {i === 4 ? <EventConfirmation /> : null}
            </React.Fragment>
          ))}
          {thinking ? <ThinkingBubble /> : null}
        </div>
      </div>
      <form className="composer" onSubmit={(e) => { e.preventDefault(); send(); }}>
        <Icon name="auto_awesome" size={20} color="var(--crystal-300)" />
        <input
          placeholder="ถามอะไรก็ได้..."
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          aria-label="พิมพ์ข้อความ"
        />
        <button type="button" className="send" style={{ background: "transparent", boxShadow: "none", color: "var(--fg-2)" }} aria-label="พูด">
          <Icon name="mic" size={20} />
        </button>
        <button type="submit" className="send" aria-label="ส่ง">
          <Icon name="arrow_upward" filled size={20} />
        </button>
      </form>
    </>
  );
}

Object.assign(window, { ChatScreen });
