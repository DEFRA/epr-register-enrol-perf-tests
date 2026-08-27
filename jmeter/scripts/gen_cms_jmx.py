#!/usr/bin/env python3
"""Generate case-management-journey.jmx for the EPR case management system."""

import sys


# ---------------------------------------------------------------------------
# Low-level XML helpers
# ---------------------------------------------------------------------------

def indent(text, n):
    prefix = "  " * n
    return "\n".join(prefix + line if line.strip() else line for line in text.split("\n"))


def prop(kind, name, value):
    return f'<{kind}Prop name="{name}">{value}</{kind}Prop>'


def bool_prop(name, val):
    return prop("bool", name, str(val).lower())


def string_prop(name, val):
    return f'<stringProp name="{name}">{val}</stringProp>'


def int_prop(name, val):
    return prop("int", name, str(val))


# ---------------------------------------------------------------------------
# JMeter element builders
# ---------------------------------------------------------------------------

def http_defaults():
    return f"""
<ConfigTestElement guiclass="HttpDefaultsGui" testclass="ConfigTestElement"
                   testname="HTTP Request Defaults" enabled="true">
  <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
    <collectionProp name="Arguments.arguments"/>
  </elementProp>
  {string_prop("HTTPSampler.domain", "${BASE_URL}")}
  {string_prop("HTTPSampler.port", "${PORT}")}
  {string_prop("HTTPSampler.protocol", "${PROTOCOL}")}
  {string_prop("HTTPSampler.contentEncoding", "UTF-8")}
  {bool_prop("HTTPSampler.follow_redirects", True)}
  {bool_prop("HTTPSampler.auto_redirects", False)}
  {bool_prop("HTTPSampler.use_keepalive", True)}
</ConfigTestElement>
<hashTree/>
""".strip()


def cookie_manager():
    return """
<CookieManager guiclass="CookiePanel" testclass="CookieManager"
               testname="HTTP Cookie Manager" enabled="true">
  <boolProp name="CookieManager.clearEachIteration">true</boolProp>
  <boolProp name="CookieManager.controlledByThreadGroup">false</boolProp>
</CookieManager>
<hashTree/>
""".strip()


def csv_dataset(filename, variables, delimiter=",", quoted=True, recycle=True, stop_on_eof=False, sharing="shareMode.all"):
    # Build filename prop separately so Python substitutes `filename` correctly
    # and ${DATA_DIR} is kept as a literal JMeter variable reference.
    fname_prop = string_prop("filename", "${DATA_DIR}/" + filename)
    return f"""
<CSVDataSet guiclass="TestBeanGUI" testclass="CSVDataSet" testname="CSV Data: {filename}" enabled="true">
  {fname_prop}
  {string_prop("variableNames", variables)}
  {string_prop("delimiter", delimiter)}
  {bool_prop("quotedData", quoted)}
  {bool_prop("recycle", recycle)}
  {bool_prop("stopThread", stop_on_eof)}
  {string_prop("shareMode", sharing)}
  {string_prop("fileEncoding", "UTF-8")}
  <boolProp name="ignoreFirstLine">true</boolProp>
</CSVDataSet>
<hashTree/>
""".strip()


def regex_extractor(var_name, regex, group=1, apply_to="body", default="NOT_FOUND"):
    # apply_to: body | headers | url
    apply_map = {"body": "false", "headers": "true", "url": "false"}
    # For headers we use a different field flag
    if apply_to == "headers":
        field = "Response Headers"
    elif apply_to == "url":
        field = "URL"
    else:
        field = "Body"
    return f"""
<RegexExtractor guiclass="RegexExtractorGui" testclass="RegexExtractor"
                testname="Extract {var_name}" enabled="true">
  {string_prop("RegexExtractor.useHeaders", "true" if apply_to == "headers" else ("URL" if apply_to == "url" else "false"))}
  {string_prop("RegexExtractor.refname", var_name)}
  {string_prop("RegexExtractor.regex", regex)}
  {string_prop("RegexExtractor.template", f"${group}$")}
  {string_prop("RegexExtractor.default", default)}
  {string_prop("RegexExtractor.match_no", "1")}
</RegexExtractor>
<hashTree/>
""".strip()


def response_assertion(code):
    return f"""
<ResponseAssertion guiclass="AssertionGui" testclass="ResponseAssertion"
                   testname="Assert HTTP {code}" enabled="true">
  <collectionProp name="Asserion.test_strings">
    <stringProp name="49586">{code}</stringProp>
  </collectionProp>
  <stringProp name="Assertion.custom_message"/>
  <stringProp name="Assertion.test_field">Assertion.response_code</stringProp>
  <boolProp name="Assertion.assume_success">false</boolProp>
  <intProp name="Assertion.test_type">8</intProp>
</ResponseAssertion>
<hashTree/>
""".strip()


def get_sampler(step, name, path, extras=""):
    return f"""
<!-- {step} -->
<HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy"
                  testname="{step} {name}" enabled="true">
  {string_prop("HTTPSampler.path", path)}
  {string_prop("HTTPSampler.method", "GET")}
  {bool_prop("HTTPSampler.follow_redirects", True)}
  {bool_prop("HTTPSampler.auto_redirects", False)}
  {bool_prop("HTTPSampler.use_keepalive", True)}
  <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
    <collectionProp name="Arguments.arguments"/>
  </elementProp>
</HTTPSamplerProxy>
<hashTree>
  {extras}
</hashTree>
""".strip()


def post_args(*pairs):
    """Build the Arguments collectionProp for POST params."""
    items = []
    for name, value in pairs:
        items.append(f"""
      <elementProp name="{name}" elementType="HTTPArgument">
        <boolProp name="HTTPArgument.always_encode">true</boolProp>
        {string_prop("Argument.name", name)}
        {string_prop("Argument.value", value)}
        {string_prop("Argument.metadata", "=")}
      </elementProp>""")
    return "\n".join(items)


def post_sampler(step, name, path, args_pairs, follow_redirect=True, extras=""):
    follow = str(follow_redirect).lower()
    args_xml = post_args(*args_pairs)
    return f"""
<!-- {step} -->
<HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy"
                  testname="{step} {name}" enabled="true">
  {string_prop("HTTPSampler.path", path)}
  {string_prop("HTTPSampler.method", "POST")}
  {bool_prop("HTTPSampler.follow_redirects", follow_redirect)}
  {bool_prop("HTTPSampler.auto_redirects", False)}
  {bool_prop("HTTPSampler.use_keepalive", True)}
  <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
    <collectionProp name="Arguments.arguments">
      {args_xml}
    </collectionProp>
  </elementProp>
</HTTPSamplerProxy>
<hashTree>
  {extras}
</hashTree>
""".strip()


def simple_controller(name, *children):
    body = "\n".join(children)
    return f"""
<GenericSampler guiclass="LogicControllerGui" testclass="GenericSampler"
                testname="{name}" enabled="true"/>
<hashTree>
  {body}
</hashTree>
""".strip()


# Actually use GenericController which is not right. Use the real one:
def logic_controller(name, *children):
    body = "\n".join(children)
    return f"""
<GenericController guiclass="LogicControllerGui" testclass="GenericController"
                   testname="{name}" enabled="true"/>
<hashTree>
  {body}
</hashTree>
""".strip()


def if_controller(name, condition, *children):
    body = "\n".join(children)
    return f"""
<IfController guiclass="IfControllerPanel" testclass="IfController"
              testname="{name}" enabled="true">
  {string_prop("IfController.condition", condition)}
  <boolProp name="IfController.evaluateAll">false</boolProp>
  <boolProp name="IfController.useExpression">true</boolProp>
</IfController>
<hashTree>
  {body}
</hashTree>
""".strip()


def thread_group(name, children_str, threads, loops, ramp=1):
    body = children_str
    return f"""
<ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup"
             testname="{name}" enabled="true">
  {string_prop("ThreadGroup.on_sample_error", "stopthread")}
  <elementProp name="ThreadGroup.main_controller" elementType="LoopController"
               guiclass="LoopControlPanel" testclass="LoopController"
               testname="Loop Controller" enabled="true">
    <boolProp name="LoopController.continue_forever">false</boolProp>
    {int_prop("LoopController.loops", loops)}
  </elementProp>
  {int_prop("ThreadGroup.num_threads", threads)}
  {int_prop("ThreadGroup.ramp_time", ramp)}
  {bool_prop("ThreadGroup.scheduler", False)}
</ThreadGroup>
<hashTree>
  {body}
</hashTree>
""".strip()


# ---------------------------------------------------------------------------
# Re-usable journey blocks
# ---------------------------------------------------------------------------

CRUMB_EXTRACTOR = regex_extractor(
    "crumb_token",
    r'name="crumb"\s+value="([^"]+)"',
    group=1,
    apply_to="body",
    default="CRUMB_NOT_FOUND"
)

WORK_ITEM_ID_EXTRACTOR = regex_extractor(
    "workItemId",
    r"Location: /work-items/([^\r\n]+)",
    group=1,
    apply_to="headers",
    default="WORK_ITEM_ID_NOT_FOUND"
)


def login_steps():
    """GET login page + POST stub login."""
    step1 = get_sampler(
        "01", "GET stub login page",
        "/auth/stub/login",
        extras=CRUMB_EXTRACTOR
    )
    step2 = post_sampler(
        "02", "POST stub login",
        "/auth/stub/login",
        [("nation", "${nation}"), ("crumb", "${crumb_token}")]
    )
    return f"{step1}\n\n{step2}"


def create_work_item_steps():
    """Kept for reference only — not used; workItemId now comes from CSV."""
    raise RuntimeError("create_work_item_steps() is disabled; seed work items first")


def get_detail_and_crumb(step_num):
    """GET /work-items/${workItemId} and extract crumb."""
    return get_sampler(
        f"{step_num:02d}", "GET work-item detail (refresh crumb)",
        "/work-items/${workItemId}",
        extras=CRUMB_EXTRACTOR
    )


def complete_task(step_num, task_id):
    return post_sampler(
        f"{step_num:02d}", f"POST complete task {task_id}",
        "/work-items/${workItemId}/tasks/" + task_id + "/complete",
        [("crumb", "${crumb_token}")]
    )


def apply_action(step_num, action_id):
    return post_sampler(
        f"{step_num:02d}", f"POST action {action_id}",
        "/work-items/${workItemId}/actions/" + action_id,
        [("crumb", "${crumb_token}")]
    )


def submitted_state_steps(start):
    n = start
    steps = []
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(complete_task(n, "verify-organisation-details")); n += 1
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(complete_task(n, "confirm-application-completeness")); n += 1
    return n, "\n\n".join(steps)


def duly_made_state_steps(start):
    n = start
    steps = []
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(complete_task(n, "confirm-registration-fee-paid")); n += 1
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(apply_action(n, "payment-received")); n += 1
    return n, "\n\n".join(steps)


def assessment_state_steps(start):
    n = start
    steps = []
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(complete_task(n, "review-compliance-history")); n += 1
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(complete_task(n, "assess-technical-capacity")); n += 1
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(complete_task(n, "assess-financial-capacity")); n += 1
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(apply_action(n, "submit-for-decision")); n += 1
    return n, "\n\n".join(steps)


def awaiting_decision_task_step(start):
    n = start
    steps = []
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(complete_task(n, "record-decision-rationale")); n += 1
    return n, "\n\n".join(steps)


def approve_steps(start):
    n = start
    steps = []
    steps.append(get_sampler(
        f"{n:02d}", "GET approve interstitial",
        "/work-items/re-accreditation/${workItemId}/approve",
        extras=CRUMB_EXTRACTOR
    )); n += 1
    steps.append(post_sampler(
        f"{n:02d}", "POST approve determination",
        "/work-items/re-accreditation/${workItemId}/approve",
        [("decisionNote", "Approved after full assessment."), ("crumb", "${crumb_token}")]
    )); n += 1
    return n, "\n\n".join(steps)


def reject_step(start):
    n = start
    steps = []
    steps.append(get_detail_and_crumb(n)); n += 1
    steps.append(post_sampler(
        f"{n:02d}", "POST action reject",
        "/work-items/${workItemId}/actions/reject",
        [("crumb", "${crumb_token}")]
    )); n += 1
    return n, "\n\n".join(steps)


def query_steps(start):
    n = start
    steps = []
    steps.append(get_sampler(
        f"{n:02d}", "GET query form",
        "/work-items/${workItemId}/query",
        extras=CRUMB_EXTRACTOR
    )); n += 1
    steps.append(post_sampler(
        f"{n:02d}", "POST submit query",
        "/work-items/${workItemId}/query",
        [
            ("sections", "prn-tonnage"),
            ("sections", "business-plan"),
            ("reason",   "Query raised on tonnage figures and business plan costings. Please provide supporting evidence."),
            ("crumb",    "${crumb_token}"),
        ]
    )); n += 1
    return n, "\n\n".join(steps)


def withdraw_confirm_steps(start, action_id_var="${withdrawActionId}"):
    n = start
    steps = []
    steps.append(get_sampler(
        f"{n:02d}", "GET withdraw confirm page",
        f"/work-items/${{workItemId}}/actions/{action_id_var}/confirm",
        extras=CRUMB_EXTRACTOR
    )); n += 1
    steps.append(post_sampler(
        f"{n:02d}", "POST confirm withdrawal",
        f"/work-items/${{workItemId}}/actions/{action_id_var}/confirm",
        [
            ("note",  "Withdrawn as part of performance test."),
            ("crumb", "${crumb_token}"),
        ]
    )); n += 1
    return n, "\n\n".join(steps)


# ---------------------------------------------------------------------------
# Build complete journey step sequences
# ---------------------------------------------------------------------------

def build_approval_journey():
    # workItemId comes from CSV; start processing immediately after login.
    parts = []
    parts.append(logic_controller("Login", login_steps()))

    n, s = submitted_state_steps(3)
    parts.append(logic_controller("Submitted State — Complete Tasks", s))

    n, s = duly_made_state_steps(n)
    parts.append(logic_controller("Duly-Made State — Payment Received", s))

    n, s = assessment_state_steps(n)
    parts.append(logic_controller("Assessment State — Complete Tasks", s))

    n, s = awaiting_decision_task_step(n)
    parts.append(logic_controller("Awaiting Decision — Record Rationale", s))

    n, s = approve_steps(n)
    parts.append(logic_controller("Approve Determination", s))

    return "\n\n".join(parts)


def build_refusal_journey():
    parts = []
    parts.append(logic_controller("Login", login_steps()))

    n, s = submitted_state_steps(3)
    parts.append(logic_controller("Submitted State — Complete Tasks", s))

    n, s = duly_made_state_steps(n)
    parts.append(logic_controller("Duly-Made State — Payment Received", s))

    n, s = assessment_state_steps(n)
    parts.append(logic_controller("Assessment State — Complete Tasks", s))

    n, s = awaiting_decision_task_step(n)
    parts.append(logic_controller("Awaiting Decision — Record Rationale", s))

    n, s = reject_step(n)
    parts.append(logic_controller("Refuse Determination", s))

    return "\n\n".join(parts)


def build_query_journey():
    parts = []
    parts.append(logic_controller("Login", login_steps()))

    n, s = submitted_state_steps(3)
    parts.append(logic_controller("Submitted State — Complete Tasks", s))

    n, s = duly_made_state_steps(n)
    parts.append(logic_controller("Duly-Made State — Payment Received", s))

    n, s = query_steps(n)
    parts.append(logic_controller("Query Application During Assessment", s))

    return "\n\n".join(parts)


def build_withdraw_submitted_journey():
    """Withdraw a work item that is still in submitted state (no tasks needed)."""
    parts = []
    parts.append(logic_controller("Login", login_steps()))
    _, s = withdraw_confirm_steps(3, "withdraw")
    parts.append(logic_controller("Withdraw at Submitted", s))
    return "\n\n".join(parts)


def build_withdraw_duly_made_journey():
    """Complete submitted tasks (auto-transitions → duly-made), then withdraw."""
    parts = []
    parts.append(logic_controller("Login", login_steps()))
    n, s = submitted_state_steps(3)
    parts.append(logic_controller("Submitted State — Complete Tasks", s))
    _, s = withdraw_confirm_steps(n, "withdraw-during-duly-made")
    parts.append(logic_controller("Withdraw During Duly-Made", s))
    return "\n\n".join(parts)


def build_withdraw_assessment_journey():
    """Complete submitted + duly-made tasks (transitions to assessment), then withdraw."""
    parts = []
    parts.append(logic_controller("Login", login_steps()))
    n, s = submitted_state_steps(3)
    parts.append(logic_controller("Submitted State — Complete Tasks", s))
    n, s = duly_made_state_steps(n)
    parts.append(logic_controller("Duly-Made State — Payment Received", s))
    _, s = withdraw_confirm_steps(n, "withdraw-during-assessment")
    parts.append(logic_controller("Withdraw During Assessment", s))
    return "\n\n".join(parts)


# ---------------------------------------------------------------------------
# Assemble the test plan
# ---------------------------------------------------------------------------

def build_test_plan():
    body_parts = []

    body_parts.append(f"""
<ConfigTestElement guiclass="HttpDefaultsGui" testclass="ConfigTestElement"
                   testname="HTTP Request Defaults" enabled="true">
  <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
    <collectionProp name="Arguments.arguments"/>
  </elementProp>
  {string_prop("HTTPSampler.domain", "${BASE_URL}")}
  {string_prop("HTTPSampler.port", "${PORT}")}
  {string_prop("HTTPSampler.protocol", "${PROTOCOL}")}
  {string_prop("HTTPSampler.contentEncoding", "UTF-8")}
  {bool_prop("HTTPSampler.follow_redirects", True)}
  {bool_prop("HTTPSampler.auto_redirects", False)}
  {bool_prop("HTTPSampler.use_keepalive", True)}
</ConfigTestElement>
<hashTree/>
""".strip())

    # Thread Group 1: Approval (3 threads)
    # CSV: workItemId pre-seeded by seed-cms-work-items.sh
    tg1_children = "\n".join([
        csv_dataset("cms-approve.csv", "workItemId,nation,material"),
        cookie_manager(),
        build_approval_journey()
    ])
    body_parts.append(thread_group(
        "Thread Group 1: Approval Journey — England / Scotland / Wales",
        tg1_children, threads=3, loops=1, ramp=2
    ))

    # Thread Group 2: Refusal (2 threads)
    tg2_children = "\n".join([
        csv_dataset("cms-refuse.csv", "workItemId,nation,material"),
        cookie_manager(),
        build_refusal_journey()
    ])
    body_parts.append(thread_group(
        "Thread Group 2: Refusal Journey — NI / England",
        tg2_children, threads=2, loops=1, ramp=2
    ))

    # Thread Group 3: Query (2 threads)
    tg3_children = "\n".join([
        csv_dataset("cms-query.csv", "workItemId,nation,material"),
        cookie_manager(),
        build_query_journey()
    ])
    body_parts.append(thread_group(
        "Thread Group 3: Query Journey — Wales / Scotland",
        tg3_children, threads=2, loops=1, ramp=2
    ))

    # Thread Group 4: Withdraw at submitted (1 thread)
    tg4a_children = "\n".join([
        csv_dataset("cms-withdraw-submitted.csv", "workItemId,nation,material"),
        cookie_manager(),
        build_withdraw_submitted_journey()
    ])
    body_parts.append(thread_group(
        "Thread Group 4a: Withdrawal at Submitted — England",
        tg4a_children, threads=1, loops=1, ramp=1
    ))

    # Thread Group 4b: Withdraw at duly-made (1 thread)
    tg4b_children = "\n".join([
        csv_dataset("cms-withdraw-duly-made.csv", "workItemId,nation,material"),
        cookie_manager(),
        build_withdraw_duly_made_journey()
    ])
    body_parts.append(thread_group(
        "Thread Group 4b: Withdrawal at Duly-Made — NI",
        tg4b_children, threads=1, loops=1, ramp=1
    ))

    # Thread Group 4c: Withdraw at assessment (1 thread)
    tg4c_children = "\n".join([
        csv_dataset("cms-withdraw-assessment.csv", "workItemId,nation,material"),
        cookie_manager(),
        build_withdraw_assessment_journey()
    ])
    body_parts.append(thread_group(
        "Thread Group 4c: Withdrawal at Assessment — Scotland",
        tg4c_children, threads=1, loops=1, ramp=1
    ))

    body = "\n\n".join(body_parts)

    plan = f"""<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0" jmeter="5.6.3">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan"
              testname="Case Management — Re-accreditation Performance Tests" enabled="true">
      <stringProp name="TestPlan.comments">Performance test — all re-accreditation work-item lifecycle journeys.
Pre-seed work items with: jmeter/scripts/seed-cms-work-items.sh

Thread Groups (parallel):
  1. Approval  (3 threads) England/plastic, Scotland/steel, Wales/paper
  2. Refusal   (2 threads) NI/glass, England/aluminium
  3. Query     (2 threads) Wales/wood, Scotland/plastic
  4a. Withdraw at submitted (1 thread) England/steel
  4b. Withdraw at duly-made (1 thread) NI/paper
  4c. Withdraw at assessment (1 thread) Scotland/glass
Total: 10 pre-seeded work items processed concurrently.</stringProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.tearDown_on_shutdown">false</boolProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments"
                   guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables">
        <collectionProp name="Arguments.arguments">
          <elementProp name="BASE_URL" elementType="Argument">
            <stringProp name="Argument.name">BASE_URL</stringProp>
            <stringProp name="Argument.value">${{__P(base_url,localhost)}}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="PORT" elementType="Argument">
            <stringProp name="Argument.name">PORT</stringProp>
            <stringProp name="Argument.value">${{__P(port,5001)}}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="PROTOCOL" elementType="Argument">
            <stringProp name="Argument.name">PROTOCOL</stringProp>
            <stringProp name="Argument.value">${{__P(protocol,http)}}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="DATA_DIR" elementType="Argument">
            <stringProp name="Argument.name">DATA_DIR</stringProp>
            <stringProp name="Argument.value">${{__P(data_dir,jmeter/data)}}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
        </collectionProp>
      </elementProp>
    </TestPlan>
    <hashTree>
{indent(body, 3)}
    </hashTree>
  </hashTree>
</jmeterTestPlan>
"""
    return plan


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "case-management-journey.jmx"
    xml = build_test_plan()
    with open(out, "w") as f:
        f.write(xml)
    print(f"Written {out} ({len(xml):,} bytes)")
