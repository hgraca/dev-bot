---
date: 2026-10-02
keywords: ["otel", "laravel", "console", "span-isolation", "long-running-command"]
aliases: ["artisan command span", "kafka:consume trace merge", "Command::execute hook"]
trigger-on: ["opentelemetry-console-command-span", "per-message-span-isolation"]
---

## opentelemetry-auto-laravel wraps Illuminate\Console\Command::execute in one span for the whole command

The `opentelemetry-auto-laravel` instrumentation hooks `Illuminate\Console\Command::execute` unconditionally (`src/LaravelInstrumentation.php` registers `Hooks\Illuminate\Console\Command`, and that hook never consults `shouldTraceCli()`, which only gates the Kernel/Artisan-handler span). A long-running artisan command — a Kafka consumer's `while (true)` loop, a worker-style command — therefore runs its entire loop under a single active `Command <name>` span, and anything that reads the current context inside the loop (dispatch-time trace propagation, `traceContextHeaders()`, `addTag()`) sees that one span. Every per-iteration span or envelope must explicitly start an isolated root (`SpanBuilder::setParent(false)`, or a helper that does so) or all iterations collapse into a single trace. A helper that only _attaches an extracted root context_ (extract a W3C traceparent, then `Context::storage()->attach()`) does not detach the ambient command span, so it cannot isolate iterations that carry no traceparent — only an explicit no-parent span can.
