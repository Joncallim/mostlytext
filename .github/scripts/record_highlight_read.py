"""LLDB callback for the unchanged SwiftTreeSitter assertion in an owned CI fixture."""
import json
import os
from pathlib import Path

import lldb


def capture(frame, _location, _internal):
    values = {}
    for name in ['byteOffset', 'limit', 'chunkSize', 'location', 'end']:
        value = frame.FindVariable(name)
        values[name] = value.GetValueAsSigned() if value.IsValid() and value.GetError().Success() else None
    options = lldb.SBExpressionOptions()
    options.SetLanguage(lldb.eLanguageTypeSwift)
    options.SetIgnoreBreakpoints(True)
    options.SetTryAllThreads(False)
    options.SetTimeoutInMicroSeconds(1000000)
    length = frame.EvaluateExpression('self.utf16.count', options)
    values['text_utf16_length'] = (length.GetValueAsSigned()
                                   if length.IsValid() and length.GetError().Success() else None)
    values['length_diagnostic'] = str(length.GetError())[:1000]
    thread = frame.GetThread()
    values['stack'] = [str(thread.GetFrameAtIndex(i)) for i in range(min(thread.GetNumFrames(), 48))]
    output = Path(os.environ['HIGHLIGHT_READ_DIAGNOSTICS']) / 'assertion-frame.json'
    output.write_text(json.dumps(values, indent=2) + '\n')
    print('HIGHLIGHT_READ_ASSERTION_FRAME ' + json.dumps(values), flush=True)
    return False  # Continue into the original assertion; never turn the stop into a pass.
