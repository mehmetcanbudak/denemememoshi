-- D51's Resume card for a held tool step and the user's answer on it. The card record lives in
-- `cards`; this row binds it to the step's Pi tool task and records how far the answer got:
-- open (no answer yet), decided (Pi's call is open and still needs the answer), noted (Pi had
-- already ended the call), dispatched (Run again let exactly one new execution through
-- Memoshi's dispatch gate), settled (Pi committed the call's result after the answer).
CREATE TABLE resume_steps (
  card_id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  runtime_task_key TEXT NOT NULL,
  action TEXT CHECK (action IN ('run_again', 'skip', 'mark_done')),
  state TEXT NOT NULL CHECK (state IN ('open', 'decided', 'noted', 'dispatched', 'settled')),
  created_at INTEGER NOT NULL,
  decided_at INTEGER,
  CHECK ((state = 'open') = (action IS NULL)),
  CHECK ((state = 'open') = (decided_at IS NULL)),
  CHECK (state != 'dispatched' OR action = 'run_again'),
  FOREIGN KEY (conversation_id, runtime_task_key)
    REFERENCES policy_tool_calls(conversation_id, runtime_task_key)
);
-- At most one unanswered card and one unapplied answer per step at a time.
CREATE UNIQUE INDEX resume_steps_one_open ON resume_steps(conversation_id, runtime_task_key)
  WHERE state = 'open';
CREATE UNIQUE INDEX resume_steps_one_decided ON resume_steps(conversation_id, runtime_task_key)
  WHERE state = 'decided';
