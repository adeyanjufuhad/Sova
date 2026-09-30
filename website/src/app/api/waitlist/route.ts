import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const ROLES = new Set(["member", "admin", "collector"]);

// Accepts 080..., 234 80..., +234 80... and returns +2348012345678
function normalisePhone(raw: string): string | null {
  const digits = raw.replace(/[^\d+]/g, "").replace(/^\+/, "");
  if (/^0[789][01]\d{8}$/.test(digits)) return `+234${digits.slice(1)}`;
  if (/^234[789][01]\d{8}$/.test(digits)) return `+${digits}`;
  return null;
}

const clean = (v: unknown, max: number) => (typeof v === "string" ? v.trim().slice(0, max) : "");

export async function POST(req: Request) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) {
    return NextResponse.json({ error: "The waitlist isn't open yet. Please check back soon." }, { status: 503 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  // Honeypot: pretend success so bots move on.
  if (clean(body.website, 200)) return NextResponse.json({ ok: true });

  const name = clean(body.name, 80);
  const phone = normalisePhone(clean(body.phone, 30));
  const role = clean(body.role, 20);
  const city = clean(body.city, 80) || null;
  const sizeNum = Number(body.group_size);
  const group_size = Number.isInteger(sizeNum) && sizeNum > 0 && sizeNum <= 5000 ? sizeNum : null;

  if (name.length < 2) return NextResponse.json({ error: "Please enter your name." }, { status: 400 });
  if (!phone) return NextResponse.json({ error: "Please enter a valid Nigerian phone number." }, { status: 400 });
  if (!ROLES.has(role)) return NextResponse.json({ error: "Please choose what describes you." }, { status: 400 });

  const supabase = createClient(url, key, { auth: { persistSession: false } });
  const { error } = await supabase.from("waitlist").insert({ name, phone, role, city, group_size });

  // 23505 = unique violation: already signed up, treat as success.
  if (error && error.code !== "23505") {
    console.error("waitlist insert failed", error);
    return NextResponse.json({ error: "We couldn't save that just now. Please try again." }, { status: 500 });
  }
  return NextResponse.json({ ok: true });
}
