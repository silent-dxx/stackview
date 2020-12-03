#!/usr/bin/env python
# coding=utf-8

import json
import vim
import sys, os
import importlib

sys.path.append(sys.path[0] + '/lib')

def search_mapping(mapping, fullname):
    match_list = []
    for mapitem in mapping:
        if (fullname.startswith(mapitem)):
            match_list.append(mapitem)

    max_len = 0
    matched = None
    for m in match_list:
        l = len(m)
        if l > max_len:
            max_len = l
            matched = m

    if matched:
        convert_filename = mapping[matched] + fullname[max_len:]
        return convert_filename
    else:
        return fullname

def load_config():
    from lib.pygdbmi import gdbmiparser
    from pprint import pprint

    filename = vim.eval('s:stackview_config_path')

    file_mapping = {}
    stack_list = []

    # load config file
    with open(filename) as f:
        confcode = f.read()
    confbyte = compile(confcode, "<string>", "exec")
    exec(confbyte)
    stack_list_len = len(stack_list)

    # Initialize some variables
    vim.command('let b:tlist_wp_count = {}'.format(stack_list_len))
    vim.command('let b:tlist_wp_list = \'\'')

    for line_num in range(stack_list_len):
        response = gdbmiparser.parse_response(stack_list[line_num].replace('\n', '').replace('\r', ''))
        stack_info = response['payload']['stack']

        vim.command('let b:tlist_wp_list = b:tlist_wp_list . \'  {}\' . "\n"'.format(stack_info[0]['func']))

        vim.command('let b:tlist_fp_{}_count = {}'.format(line_num, len(stack_info)))
        vim.command('let b:tlist_fp_{}_list = \'\''.format(line_num))

        item_index = 0
        item_max   = len(stack_info) - 1
        for item in stack_info:
            vim.command('let b:tlist_fp_{}_list = b:tlist_fp_{}_list . \'  {}()\' . "\n"'.format(line_num, line_num, item['func']))
            vim.command('let b:tlist_fp_{}_{}_fullname = \'{}\''.format(line_num, item_index, search_mapping(file_mapping, item['fullname'])))
            vim.command('let b:tlist_fp_{}_{}_line = {}'.format(line_num, item_index, item['line']))
            item_index += 1

