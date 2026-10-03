import type { FastifyReply, FastifyRequest } from "fastify";

import { AppError } from "../lib/errors.js";
import type { TokenService } from "./tokens.js";

declare module "fastify" {
  interface FastifyRequest {
    /** Set by `requireUser` from a valid access token. */
    userId?: string;
  }
}

/** preHandler that requires "Authorization: Bearer <access token>". */
export function requireUser(tokens: TokenService) {
  return async (req: FastifyRequest, _reply: FastifyReply) => {
    const header = req.headers.authorization ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(header);
    if (!match?.[1]) throw new AppError(401, "unauthorized", "Please sign in.");
    req.userId = await tokens.verifyAccess(match[1]);
  };
}

/** The signed-in user's id inside a route guarded by `requireUser`. */
export function userIdOf(req: FastifyRequest): string {
  if (!req.userId) throw new AppError(401, "unauthorized", "Please sign in.");
  return req.userId;
}
