import type { FastifyError, FastifyInstance } from "fastify";
import { ZodError } from "zod";

/**
 * An error safe to show to the user. Everything else becomes a generic 500
 * so internal details never leak.
 */
export class AppError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export const notFound = (what: string) => new AppError(404, "not_found", `${what} not found.`);
export const forbidden = (message = "You are not allowed to do that.") => new AppError(403, "forbidden", message);
export const conflict = (code: string, message: string) => new AppError(409, code, message);

/** All errors leave the API as { error: { code, message, details? } }. */
export function registerErrorHandler(app: FastifyInstance) {
  app.setErrorHandler((err: FastifyError | AppError | ZodError | Error, req, reply) => {
    if (err instanceof AppError) {
      return reply.code(err.statusCode).send({ error: { code: err.code, message: err.message, details: err.details } });
    }
    if (err instanceof ZodError) {
      return reply.code(400).send({
        error: {
          code: "invalid_request",
          message: err.issues[0]?.message ?? "Invalid request.",
          details: { issues: err.issues.map((i) => ({ path: i.path.join("."), message: i.message })) },
        },
      });
    }
    const status = (err as FastifyError).statusCode;
    if (status && status >= 400 && status < 500) {
      const code = status === 429 ? "rate_limited" : (err as FastifyError).code?.toLowerCase() ?? "bad_request";
      const message = status === 429 ? "Too many attempts. Please wait and try again." : err.message;
      return reply.code(status).send({ error: { code, message } });
    }
    req.log.error({ err }, "unhandled error");
    return reply.code(500).send({ error: { code: "internal", message: "Something went wrong. Please try again." } });
  });

  app.setNotFoundHandler((_req, reply) =>
    reply.code(404).send({ error: { code: "not_found", message: "Route not found." } }),
  );
}
