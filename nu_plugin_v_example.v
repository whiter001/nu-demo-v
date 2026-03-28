module main

import io
import os
import x.json2

const plugin_name = 'v_example'

const plugin_version = '0.1.1'

fn main() {
	if os.args.len < 2 || os.args[1] != '--stdio' {
		eprintln('This plugin is intended to be run from within Nushell')
		exit(2)
	}

	run_stdio() or {
		eprintln('Plugin error: ${err}')
		exit(1)
	}
}

fn run_stdio() ! {
	mut stdout := os.stdout()
	mut stderr := os.stderr()

	stdout.write_string('\x04json\n')!

	version := detect_nushell_version()!
	send_message(mut stdout, hello_message(version))!

	mut reader := io.new_buffered_reader(reader: os.stdin())
	for {
		line := reader.read_line() or { break }
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}

		message := json2.decode[map[string]json2.Any](trimmed) or {
			stderr.write_string('Parse error: ${err}\nReceived: ${trimmed}\n')!
			continue
		}

		handle_message(message, mut stdout, mut stderr)!
	}
}

fn detect_nushell_version() !string {
	if env_version := os.getenv_opt('NUSHELL_VERSION') {
		trimmed := env_version.trim_space()
		if trimmed.len > 0 {
			return trimmed
		}
	}

	result := os.execute_opt('nu --version') or {
		return error('failed to detect Nushell version: ${err}')
	}
	version := result.output.trim_space()
	if version.len == 0 {
		return error('nu --version returned an empty version string')
	}
	return version
}

fn handle_message(message map[string]json2.Any, mut stdout os.File, mut stderr os.File) ! {
	if hello_any := message['Hello'] {
		handle_hello(hello_any)!
		return
	}

	if 'Goodbye' in message {
		exit(0)
	}

	if signal_any := message['Signal'] {
		handle_signal(signal_any, mut stderr)!
		return
	}

	if call_any := message['Call'] {
		handle_call(call_any, mut stdout)!
		return
	}

	return error('unsupported message: ${json2.encode(message, json2.EncoderOptions{})}')
}

fn handle_hello(hello_any json2.Any) ! {
	hello := expect_object(hello_any, 'Hello')!

	protocol := expect_string(get_field(hello, 'protocol', 'Hello')!, 'Hello.protocol')!
	if protocol != 'nu-plugin' {
		return error('unexpected protocol: ${protocol}')
	}

	version := expect_string(get_field(hello, 'version', 'Hello')!, 'Hello.version')!
	expected_version := detect_nushell_version()!
	if version != expected_version {
		return error('Version mismatch: expected ${expected_version}, got ${version}')
	}
}

fn handle_signal(signal_any json2.Any, mut stderr os.File) ! {
	signal := expect_string(signal_any, 'Signal')!
	if signal != 'Reset' {
		stderr.write_string('Unhandled signal: ${signal}\n')!
	}
}

fn handle_call(call_any json2.Any, mut stdout os.File) ! {
	call := expect_array(call_any, 'Call')!
	if call.len != 2 {
		return error('Call payload must be [id, call]')
	}

	id := expect_int(call[0], 'Call id')!
	payload := call[1]

	match payload {
		string {
			match payload {
				'Metadata' {
					mut response := new_object()
					mut metadata := new_object()
					metadata['version'] = json2.Any(plugin_version)
					response['Metadata'] = json2.Any(metadata)
					send_call_response(mut stdout, id, response)!
				}
				'Signature' {
					send_call_response(mut stdout, id, signature_response())!
				}
				else {
					return error('Unsupported call: ${payload}')
				}
			}
		}
		map[string]json2.Any {
			if run_any := payload['Run'] {
				handle_run(id, run_any, mut stdout)!
				return
			}
			return error('Unsupported call payload: ${json2.encode(payload, json2.EncoderOptions{})}')
		}
		else {
			return error('Unsupported call payload type: ${payload}')
		}
	}
}

fn handle_run(id int, run_any json2.Any, mut stdout os.File) ! {
	run := expect_object(run_any, 'Run')!
	call_any := get_field(run, 'call', 'Run')!
	call := expect_object(call_any, 'Run.call')!
	head_any := get_field(call, 'head', 'Run.call')!
	head := expect_object(head_any, 'Run.call.head')!

	start := expect_int(get_field(head, 'start', 'Run.call.head')!, 'Run.call.head.start')!
	end := expect_int(get_field(head, 'end', 'Run.call.head')!, 'Run.call.head.end')!
	span := span_object(start, end)

	table_data := build_table_data(span)

	mut list := new_object()
	list['vals'] = json2.Any(table_data)
	list['span'] = json2.Any(span)

	mut pipeline_value := new_object()
	pipeline_value['List'] = json2.Any(list)

	mut pipeline_data := new_object()
	pipeline_data['Value'] = json2.Any([json2.Any(pipeline_value), json2.Any(json2.null)])

	mut response := new_object()
	response['PipelineData'] = json2.Any(pipeline_data)
	send_call_response(mut stdout, id, response)!
}

fn build_table_data(span map[string]json2.Any) []json2.Any {
	mut rows := []json2.Any{}
	for index in 0 .. 10 {
		mut values := new_object()
		values['one'] = json2.Any(int_value(index * 1, span))
		values['two'] = json2.Any(int_value(index * 2, span))
		values['three'] = json2.Any(int_value(index * 3, span))

		mut record := new_object()
		record['val'] = json2.Any(values)
		record['span'] = json2.Any(span)

		mut row := new_object()
		row['Record'] = json2.Any(record)
		rows << json2.Any(row)
	}
	return rows
}

fn signature_response() map[string]json2.Any {
	mut required_a := new_object()
	required_a['name'] = json2.Any('a')
	required_a['desc'] = json2.Any('Required integer parameter')
	required_a['shape'] = json2.Any('Int')

	mut required_b := new_object()
	required_b['name'] = json2.Any('b')
	required_b['desc'] = json2.Any('Required string parameter')
	required_b['shape'] = json2.Any('String')

	mut optional_opt := new_object()
	optional_opt['name'] = json2.Any('opt')
	optional_opt['desc'] = json2.Any('Optional numeric parameter')
	optional_opt['shape'] = json2.Any('Int')

	mut rest_positional := new_object()
	rest_positional['name'] = json2.Any('rest')
	rest_positional['desc'] = json2.Any('Variable-length string parameters')
	rest_positional['shape'] = json2.Any('String')

	mut help_named := new_object()
	help_named['long'] = json2.Any('help')
	help_named['short'] = json2.Any('h')
	help_named['arg'] = json2.Any(json2.null)
	help_named['required'] = json2.Any(false)
	help_named['desc'] = json2.Any('Display help information')

	mut flag_named := new_object()
	flag_named['long'] = json2.Any('flag')
	flag_named['short'] = json2.Any('f')
	flag_named['arg'] = json2.Any(json2.null)
	flag_named['required'] = json2.Any(false)
	flag_named['desc'] = json2.Any('Example boolean flag')

	mut named_named := new_object()
	named_named['long'] = json2.Any('named')
	named_named['short'] = json2.Any('n')
	named_named['arg'] = json2.Any('String')
	named_named['required'] = json2.Any(false)
	named_named['desc'] = json2.Any('Example named parameter')

	mut command := new_object()
	command['name'] = json2.Any(plugin_name)
	command['description'] = json2.Any('Demonstration plugin for V')
	command['extra_description'] = json2.Any('')
	command['required_positional'] = json2.Any([json2.Any(required_a), json2.Any(required_b)])
	command['optional_positional'] = json2.Any([json2.Any(optional_opt)])
	command['rest_positional'] = json2.Any(rest_positional)
	command['named'] = json2.Any([json2.Any(help_named), json2.Any(flag_named), json2.Any(named_named)])
	command['input_output_types'] = json2.Any([
		json2.Any([json2.Any('Any'), json2.Any('Any')]),
	])
	command['allow_variants_without_examples'] = json2.Any(true)
	command['search_terms'] = json2.Any([json2.Any('vlang'), json2.Any('example')])
	command['is_filter'] = json2.Any(false)
	command['creates_scope'] = json2.Any(false)
	command['allows_unknown_args'] = json2.Any(false)
	command['category'] = json2.Any('Experimental')

	mut sig := new_object()
	sig['sig'] = json2.Any(command)
	sig['examples'] = json2.Any([]json2.Any{})

	mut response := new_object()
	response['Signature'] = json2.Any([json2.Any(sig)])
	return response
}

fn hello_message(version string) map[string]json2.Any {
	mut hello := new_object()
	hello['protocol'] = json2.Any('nu-plugin')
	hello['version'] = json2.Any(version)
	hello['features'] = json2.Any([]json2.Any{})

	mut message := new_object()
	message['Hello'] = json2.Any(hello)
	return message
}

fn send_message(mut stdout os.File, message map[string]json2.Any) ! {
	stdout.write_string(json2.encode(message, json2.EncoderOptions{}) + '\n')!
}

fn send_call_response(mut stdout os.File, id int, response map[string]json2.Any) ! {
	mut envelope := new_object()
	envelope['CallResponse'] = json2.Any([json2.Any(id), json2.Any(response)])
	send_message(mut stdout, envelope)!
}

fn get_field(obj map[string]json2.Any, field string, context string) !json2.Any {
	return obj[field] or { return error('missing field ${context}.${field}') }
}

fn expect_object(value json2.Any, context string) !map[string]json2.Any {
	match value {
		map[string]json2.Any {
			return value
		}
		else {
			return error('${context} must be an object')
		}
	}
}

fn expect_array(value json2.Any, context string) ![]json2.Any {
	match value {
		[]json2.Any {
			return value
		}
		else {
			return error('${context} must be an array')
		}
	}
}

fn expect_string(value json2.Any, context string) !string {
	match value {
		string {
			return value
		}
		else {
			return error('${context} must be a string')
		}
	}
}

fn expect_int(value json2.Any, context string) !int {
	match value {
		int {
			return value
		}
		i64 {
			return int(value)
		}
		f64 {
			return int(value)
		}
		u64 {
			return int(value)
		}
		f32 {
			return int(value)
		}
		i32 {
			return int(value)
		}
		u32 {
			return int(value)
		}
		else {
			return error('${context} must be an integer')
		}
	}
}

fn span_object(start int, end int) map[string]json2.Any {
	mut span := new_object()
	span['start'] = json2.Any(start)
	span['end'] = json2.Any(end)
	return span
}

fn int_value(value int, span map[string]json2.Any) map[string]json2.Any {
	mut int_value := new_object()
	int_value['val'] = json2.Any(value)
	int_value['span'] = json2.Any(span)

	mut result := new_object()
	result['Int'] = json2.Any(int_value)
	return result
}

fn new_object() map[string]json2.Any {
	return map[string]json2.Any{}
}
