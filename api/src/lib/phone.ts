/** Nigerian mobile numbers: 0803..., 803..., 234803..., +234 803... -> +234803... */
export function normalisePhone(raw: string): string | null {
  const digits = raw.replace(/[^\d]/g, "");
  if (/^0[789][01]\d{8}$/.test(digits)) return `+234${digits.slice(1)}`;
  if (/^[789][01]\d{8}$/.test(digits)) return `+234${digits}`;
  if (/^234[789][01]\d{8}$/.test(digits)) return `+${digits}`;
  return null;
}

/** +2348031234567 -> 0803 123 4567 */
export function displayPhone(e164: string): string {
  if (!/^\+234\d{10}$/.test(e164)) return e164;
  const local = `0${e164.slice(4)}`;
  return `${local.slice(0, 4)} ${local.slice(4, 7)} ${local.slice(7)}`;
}
