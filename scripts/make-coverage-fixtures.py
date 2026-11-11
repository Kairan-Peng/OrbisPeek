#!/usr/bin/env python3
"""Generate one representative text-syntax fixture for every manifest suffix.

Fixtures are only previewed, never executed or installed as configuration. They
exercise basic syntax rather than claiming to be complete projects, schemas or
compiler conformance tests. No registration or file association is changed.
"""

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/QuicklookCore/Resources/file-types.json"
DEFAULT_OUTPUT = ROOT / ".build/finder-coverage"
PLACEHOLDER = "@MARKER@"

# Each group has its own syntax, including filename-only nginx. Aliases reuse
# these templates; materially different dialects are specialized below.
TEMPLATES = {
    "markdown": '''# @MARKER@

A **Markdown** preview with `inline code`.

| Name | Enabled |
| --- | --- |
| Preview | yes |

- [x] Structured sample
- [ ] Manual Finder acceptance
''',
    "json": '''{
  "coverageMarker": "@MARKER@",
  "name": "Preview fixture",
  "enabled": true,
  "items": [{"id": 1, "label": "First"}, {"id": 2, "label": "Second"}],
  "options": {"limit": 10, "empty": null}
}
''',
    "json-lines": '''{"coverageMarker":"@MARKER@","id":1,"event":"started","ok":true}
{"id":2,"event":"item","details":{"name":"First","size":42}}
{"id":3,"event":"item","details":{"name":"Second","size":84}}
{"id":4,"event":"finished","items":[1,2],"ok":true}
''',
    "json-with-comments": '''// @MARKER@
{
  "coverageMarker": "@MARKER@",
  "folders": [{"path": "."}],
  "settings": {
    "editor.wordWrap": "on", // A JSONC comment
    "preview.enabled": true,
  },
}
''',
    "json5": '''// @MARKER@
{
  coverageMarker: '@MARKER@',
  enabled: true,
  hexadecimal: 0x2a,
  items: ['first', 'second',],
  options: {limit: 10,},
}
''',
    "yaml": '''# @MARKER@
coverageMarker: "@MARKER@"
enabled: true
server:
  host: localhost
  port: 8080
items:
  - name: first
    tags: [preview, text]
''',
    "toml": '''# @MARKER@
coverage_marker = "@MARKER@"
enabled = true
[server]
host = "localhost"
port = 8080
[[items]]
name = "first"
tags = ["preview", "text"]
''',
    "properties": '''# @MARKER@
coverage.marker=@MARKER@
server.host=localhost
server.port=8080
preview.enabled=true
unicode.greeting=\\u4F60\\u597D
continued.value=first\\
  second
''',
    "ini": '''; @MARKER@
[preview]
marker=@MARKER@
enabled=true
[server]
host=localhost
port=8080
paths=documents,source
''',
    "logs": '''2026-11-11T00:00:00Z INFO @MARKER@ preview started
2026-11-11T00:00:01Z DEBUG component=loader encoding=UTF-8
2026-11-11T00:00:02Z INFO component=loader bytes=128
2026-11-11T00:00:03Z WARN component=sample action=preview-only
2026-11-11T00:00:04Z INFO component=renderer mode=code
2026-11-11T00:00:05Z INFO status=complete items=2
''',
    "plain-config": '''# @MARKER@
# Generic dependency lock syntax sample, not a package-manager lockfile.
version = 1
[[package]]
name = "preview-fixture"
version = "1.0.0"
source = "local"
''',
    "dotenv": '''# @MARKER@
COVERAGE_MARKER="@MARKER@"
PREVIEW_ENABLED=true
SERVER_HOST=localhost
SERVER_PORT=8080
DOCUMENT_ROOT='./documents'
DISPLAY_NAME='Preview fixture'
''',
    "git-config": '''# @MARKER@
[preview]
    marker = @MARKER@
    enabled = true
[core]
    autocrlf = false
[diff]
    algorithm = histogram
''',
    "swift": '''// @MARKER@
import Foundation
struct PreviewItem {
    let name: String
    let size: Int
}
let marker = "@MARKER@"
let items = [PreviewItem(name: "First", size: 42)]
let names = items.map { $0.name }
''',
    "javascript": '''// @MARKER@
const marker = "@MARKER@";
const items = [{name: "First", size: 42}];
function summarize(values) {
  return values.map((item) => `${item.name}:${item.size}`);
}
const preview = {marker, names: summarize(items)};
console.log(preview);
''',
    "typescript": '''// @MARKER@
interface PreviewItem { name: string; size: number }
const marker: string = "@MARKER@";
const items: PreviewItem[] = [{name: "First", size: 42}];
function summarize(values: PreviewItem[]): string[] {
  return values.map((item) => item.name);
}
export const preview = {marker, names: summarize(items)};
''',
    "python": '''# @MARKER@
from dataclasses import dataclass
MARKER = "@MARKER@"
@dataclass
class PreviewItem:
    name: str
    size: int
items = [PreviewItem("First", 42)]
names = [item.name for item in items]
''',
    "rust": '''// @MARKER@
const MARKER: &str = "@MARKER@";
struct PreviewItem { name: String, size: usize }
fn main() {
    let item = PreviewItem { name: "First".into(), size: 42 };
    let names = [item.name].join(", ");
    println!("{}: {} ({})", MARKER, names, item.size);
}
''',
    "go": '''// @MARKER@
package main
import "fmt"
type PreviewItem struct { Name string; Size int }
const marker = "@MARKER@"
func main() {
    item := PreviewItem{Name: "First", Size: 42}
    fmt.Printf("%s: %s (%d)\\n", marker, item.Name, item.Size)
}
''',
    "java": '''// @MARKER@
class CoverageFixture {
    private static final String MARKER = "@MARKER@";
    static String describe(String name, int size) {
        return name + ":" + size;
    }
    public static void main(String[] args) {
        System.out.println(MARKER + describe("First", 42));
    }
}
''',
    "kotlin": '''// @MARKER@
val marker = "@MARKER@"
data class PreviewItem(val name: String, val size: Int)
fun describe(item: PreviewItem): String {
    return "${item.name}:${item.size}"
}
val items = listOf(PreviewItem("First", 42))
val summary = items.map(::describe)
''',
    "c": '''/* @MARKER@ */
#ifndef COVERAGE_FIXTURE_H
#define COVERAGE_FIXTURE_H
static const char coverage_marker[] = "@MARKER@";
struct preview_item { const char *name; int size; };
static int preview_size(const struct preview_item *item) {
    return item->size;
}
#endif
''',
    "cpp": '''// @MARKER@
#pragma once
#include <string>
#include <vector>
namespace coverage {
inline constexpr const char *marker = "@MARKER@";
template <typename T> T twice(T value) { return value + value; }
struct PreviewItem { std::string name; int size; };
inline const std::vector<PreviewItem> items = {{"First", 42}};
}
''',
    "objective-c": '''// @MARKER@
#import <Foundation/Foundation.h>
@interface CoverageFixture : NSObject
- (NSString *)marker;
@end
@implementation CoverageFixture
- (NSString *)marker { return @"@MARKER@"; }
@end
''',
    "csharp": '''// @MARKER@
using System;
class CoverageFixture {
    const string Marker = "@MARKER@";
    public static string Describe(string name, int size) {
        return $"{Marker}: {name} ({size})";
    }
}
''',
    "fsharp": '''// @MARKER@
module CoverageFixture
let marker = "@MARKER@"
type PreviewItem = { Name: string; Size: int }
let describe item = sprintf "%s:%d" item.Name item.Size
let items = [{ Name = "First"; Size = 42 }]
let names = items |> List.map describe
''',
    "visual-basic": '''' @MARKER@
Module CoverageFixture
    Const Marker As String = "@MARKER@"
    Function Describe(name As String, size As Integer) As String
        Return String.Format("{0}:{1}", name, size)
    End Function
    Sub Main()
        Console.WriteLine(Marker & Describe("First", 42))
    End Sub
End Module
''',
    "shell": '''#!/bin/sh
# @MARKER@
marker='@MARKER@'
describe() {
    printf '%s:%s\\n' "$1" "$2"
}
name=First
size=42
printf '%s\\n' "$marker"
describe "$name" "$size"
''',
    "ruby": '''# @MARKER@
MARKER = "@MARKER@"
PreviewItem = Struct.new(:name, :size)
items = [PreviewItem.new("First", 42)]
def describe(item)
  "#{item.name}:#{item.size}"
end
summary = items.map { |item| describe(item) }
''',
    "php": '''<?php
// @MARKER@
$marker = "@MARKER@";
$items = array("first" => 42, "second" => 84);
function describe($name, $size) {
    return $name . ":" . $size;
}
foreach ($items as $name => $size) {
    echo describe($name, $size), "\\n";
}
?>
''',
    "lua": '''-- @MARKER@
local marker = "@MARKER@"
local items = {{name = "First", size = 42}}
local function describe(item)
    return item.name .. ":" .. item.size
end
for _, item in ipairs(items) do
    print(marker, describe(item))
end
''',
    "perl": '''# @MARKER@
use strict;
use warnings;
my $marker = '@MARKER@';
my @items = ({name => 'First', size => 42});
sub describe { my ($item) = @_; return "$item->{name}:$item->{size}"; }
for my $item (@items) {
    print $marker, ' ', describe($item), "\\n";
}
''',
    "r": '''# @MARKER@
marker <- "@MARKER@"
items <- data.frame(name = c("First", "Second"), size = c(42, 84))
describe <- function(item) {
  paste(item$name, item$size, sep = ":")
}
summary <- describe(items)
print(list(marker = marker, items = summary))
''',
    "julia": '''# @MARKER@
const MARKER = "@MARKER@"
struct PreviewItem
    name::String
    size::Int
end
describe(item::PreviewItem) = "$(item.name):$(item.size)"
items = [PreviewItem("First", 42)]
summary = describe.(items)
''',
    "dart": '''// @MARKER@
const marker = '@MARKER@';
class PreviewItem {
  final String name;
  final int size;
  const PreviewItem(this.name, this.size);
}
void main() {
  final items = [PreviewItem('First', 42)];
  print('$marker: ${items.first.name}');
}
''',
    "scala": '''// @MARKER@
object CoverageFixture {
  val marker = "@MARKER@"
  case class PreviewItem(name: String, size: Int)
  def describe(item: PreviewItem): String = s"${item.name}:${item.size}"
  val items = List(PreviewItem("First", 42))
  val summary = items.map(describe)
}
''',
    "groovy": '''// @MARKER@
def marker = '@MARKER@'
def items = [[name: 'First', size: 42]]
def describe(item) {
    "${item.name}:${item.size}"
}
def summary = items.collect { describe(it) }
println "$marker: $summary"
''',
    "sql": '''-- @MARKER@
CREATE TABLE preview_items (id INTEGER PRIMARY KEY, name VARCHAR(80), size INTEGER);
INSERT INTO preview_items (id, name, size)
VALUES (1, '@MARKER@', 42);
SELECT name, SUM(size) AS total_size
FROM preview_items
WHERE size > 0
GROUP BY name;
''',
    "css": '''/* @MARKER@ */
:root { --preview-accent: #2563eb; }
.preview::before { content: "@MARKER@"; }
.preview {
  display: grid;
  grid-template-columns: 1fr 2fr;
  color: var(--preview-accent);
  padding: 1rem;
}
''',
    "scss": '''// @MARKER@
$accent: #2563eb;
.preview {
  color: $accent;
  &::before { content: "@MARKER@"; }
  .item { padding: 1rem; }
  @media (min-width: 40rem) { display: grid; }
}
''',
    "sass": '''// @MARKER@
$accent: #2563eb
.preview
  color: $accent
  &::before
    content: "@MARKER@"
  .item
    padding: 1rem
''',
    "less": '''// @MARKER@
@accent: #2563eb;
.rounded(@radius) { border-radius: @radius; }
.preview {
  color: @accent;
  .rounded(4px);
  &::before { content: "@MARKER@"; }
}
''',
    "web-components": '''<!-- @MARKER@ -->
<script>
  const marker = "@MARKER@";
  const items = ["First", "Second"];
</script>
<article>
  <h1>{marker}</h1>
  <p>A component syntax sample.</p>
</article>
''',
    "graphql": '''"""@MARKER@"""
type PreviewItem {
  id: ID!
  name: String!
  size: Int
}
type Query {
  item(id: ID!): PreviewItem
  items: [PreviewItem!]!
}
''',
    "protobuf": '''// @MARKER@
syntax = "proto3";
package coverage;
message PreviewItem {
  string marker = 1;
  string name = 2;
  int32 size = 3;
  repeated string tags = 4;
}
''',
    "cmake": '''# @MARKER@
cmake_minimum_required(VERSION 3.20)
project(CoverageFixture LANGUAGES C)
set(COVERAGE_MARKER "@MARKER@")
set(PREVIEW_ITEMS first second)
foreach(item IN LISTS PREVIEW_ITEMS)
  message(STATUS "${COVERAGE_MARKER}: ${item}")
endforeach()
''',
    "makefile": '''# @MARKER@
COVERAGE_MARKER := @MARKER@
ITEMS := first second
.PHONY: preview clean
preview:
\t@printf '%s\\n' '$(COVERAGE_MARKER)'
\t@printf '%s\\n' '$(ITEMS)'
clean:
\t@printf '%s\\n' 'Preview fixture: no files removed'
''',
    "dockerfile": '''# @MARKER@
FROM alpine:3.20
LABEL coverage.marker="@MARKER@"
WORKDIR /preview
ENV PREVIEW_ENABLED=true
COPY . /preview
USER 65534:65534
CMD ["echo", "preview-only fixture"]
''',
    "diff": '''Subject: [PATCH] @MARKER@

diff --git a/preview.txt b/preview.txt
--- a/preview.txt
+++ b/preview.txt
@@ -1,2 +1,3 @@
-title: old
+title: @MARKER@
 enabled: true
+items: 2
''',
    "xml": '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<preview marker="@MARKER@">
  <items>
    <item id="1" enabled="true">First</item>
    <item id="2" enabled="false">Second</item>
  </items>
</preview>
''',
    "plist": '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CoverageMarker</key><string>@MARKER@</string>
  <key>Enabled</key><true/>
  <key>Items</key><array><string>First</string><string>Second</string></array>
  <key>Count</key><integer>2</integer>
</dict></plist>
''',
    "strings": '''/* @MARKER@ */
"coverage.marker" = "@MARKER@";
"preview.title" = "Preview fixture";
"preview.items" = "Items: %ld";
"preview.enabled" = "Enabled";
"preview.multiline" = "First\\nSecond";
''',
    "hcl": '''# @MARKER@
coverage_marker = "@MARKER@"
enabled = true
server = {
  host = "localhost"
  port = 8080
}
items = ["first", "second"]
''',
    "nix": '''# @MARKER@
{ lib ? null }:
let
  marker = "@MARKER@";
  items = [ "first" "second" ];
in {
  inherit marker items;
  enabled = true;
}
''',
    "zig": '''// @MARKER@
const std = @import("std");
const marker = "@MARKER@";
const PreviewItem = struct { name: []const u8, size: usize };
pub fn main() void {
    const item = PreviewItem{ .name = "First", .size = 42 };
    std.debug.print("{s}: {s} ({d})\\n", .{ marker, item.name, item.size });
}
''',
    "elixir": '''# @MARKER@
defmodule CoverageFixture do
  @marker "@MARKER@"
  def describe(%{name: name, size: size}) do
    "#{@marker}: #{name}:#{size}"
  end
  def items, do: [%{name: "First", size: 42}]
end
''',
    "erlang": '''%% @MARKER@
-module(coverage_fixture).
-export([marker/0, describe/1]).
marker() -> "@MARKER@".
describe(#{name := Name, size := Size}) ->
    io_lib:format("~s:~p", [Name, Size]).
''',
    "haskell": '''-- @MARKER@
module CoverageFixture where
marker :: String
marker = "@MARKER@"
data PreviewItem = PreviewItem { name :: String, size :: Int }
describe :: PreviewItem -> String
describe item = name item ++ ":" ++ show (size item)
items = [PreviewItem "First" 42]
''',
    "clojure": ''';; @MARKER@
(ns coverage.fixture)
(def marker "@MARKER@")
(def items [{:name "First" :size 42}])
(defn describe [{:keys [name size]}]
  (str name ":" size))
(def summary (mapv describe items))
''',
    "lisp": ''';; @MARKER@
(defparameter *coverage-marker* "@MARKER@")
(defstruct preview-item name size)
(defun describe-item (item)
  (format nil "~A:~D" (preview-item-name item) (preview-item-size item)))
(defparameter *items*
  (list (make-preview-item :name "First" :size 42)))
''',
    "scheme": ''';; @MARKER@
(define coverage-marker "@MARKER@")
(define (describe name size)
  (string-append name ":" (number->string size)))
(define items '(("First" 42) ("Second" 84)))
(define summary
  (map (lambda (item) (apply describe item)) items))
''',
    "ocaml": '''(* @MARKER@ *)
let marker = "@MARKER@"
type preview_item = { name : string; size : int }
let describe item = Printf.sprintf "%s:%d" item.name item.size
let items = [{ name = "First"; size = 42 }]
let summary = List.map describe items
''',
    "verilog": '''// @MARKER@
module coverage_fixture (
    input wire clock,
    input wire enabled,
    output reg [7:0] count
);
    initial count = 0;
    always @(posedge clock) if (enabled) count <= count + 1;
endmodule
''',
    "vhdl": '''-- @MARKER@
library ieee;
use ieee.std_logic_1164.all;
package coverage_fixture is
  constant marker : string := "@MARKER@";
  type preview_item is record
    enabled : boolean;
    size : integer;
  end record;
end package coverage_fixture;
''',
    "assembly": '''; @MARKER@
section .rodata
coverage_marker: db "@MARKER@", 0
section .text
global coverage_add
coverage_add:
    mov eax, edi
    add eax, esi
    ret
''',
    "powershell": '''# @MARKER@
$Marker = '@MARKER@'
function Get-PreviewDescription {
    param([string]$Name, [int]$Size)
    '{0}:{1}' -f $Name, $Size
}
$Items = @(@{ Name = 'First'; Size = 42 })
$Items | ForEach-Object { Get-PreviewDescription $_.Name $_.Size }
''',
    "batch": '''@echo off
rem @MARKER@
set "COVERAGE_MARKER=@MARKER@"
set "PREVIEW_NAME=First"
set "PREVIEW_SIZE=42"
echo %COVERAGE_MARKER%
if defined PREVIEW_NAME (
  echo %PREVIEW_NAME%:%PREVIEW_SIZE%
)
''',
    "latex": '''% @MARKER@
\\documentclass{article}
\\usepackage[T1]{fontenc}
\\title{Coverage fixture}
\\begin{document}
\\maketitle
\\section{Preview fixture}
A \\textbf{structured} document with $x^2 + y^2$.
\\begin{itemize}\\item First\\item Second\\end{itemize}
\\end{document}
''',
    "bibtex": '''@article{coverageFixture,
  title = {@MARKER@},
  author = {Example, Alice and Sample, Bob},
  journal = {Preview Samples},
  year = {2026},
  volume = {1},
  pages = {1--3},
  note = {Representative BibTeX syntax}
}
''',
    "restructuredtext": '''@MARKER@
============================================================

A **reStructuredText** preview with ``inline code``.

* First item
* Second item

.. note:: This is a syntax sample, not an executable document.
''',
    "asciidoc": '''= @MARKER@
:author: Preview Fixture
:toc:

== Structured sample
A *bold* label and `inline code`.

* First item
* Second item
''',
    "wasm-text": ''';; @MARKER@
(module
  (memory (export "memory") 1)
  (data (i32.const 0) "@MARKER@")
  (func (export "add") (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add))
''',
    "shader": '''#version 330 core
// @MARKER@
in vec2 textureCoordinate;
out vec4 fragmentColor;
uniform vec4 tint;
void main() {
    fragmentColor = vec4(textureCoordinate, 0.0, 1.0) * tint;
}
''',
    "cuda": '''// @MARKER@
static const char coverage_marker[] = "@MARKER@";
__global__ void increment(int *values, int count) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index < count) {
        values[index] += 1;
    }
}
''',
    "arduino": '''// @MARKER@
#include <Arduino.h>
const char marker[] = "@MARKER@";
void setup() {
    Serial.begin(9600);
    Serial.println(marker);
}
void loop() {
    delay(1000);
}
''',
    "d": '''// @MARKER@
module coverage_fixture;
enum marker = "@MARKER@";
struct PreviewItem { string name; int size; }
string describe(PreviewItem item) {
    return item.name;
}
''',
    "nim": '''# @MARKER@
const marker = "@MARKER@"
type PreviewItem = object
  name: string
  size: int
proc describe(item: PreviewItem): string =
  item.name & ":" & $item.size
let items = @[PreviewItem(name: "First", size: 42)]
''',
    "awk": '''# @MARKER@
BEGIN {
    marker = "@MARKER@"
    FS = ","
    print marker
}
NF >= 2 { total += $2; count++ }
END { printf "items=%d total=%d\\n", count, total }
''',
    "tcl": '''# @MARKER@
set marker "@MARKER@"
proc describe {name size} {
    return "${name}:${size}"
}
set items {{First 42} {Second 84}}
foreach item $items {
    puts [describe {*}$item]
}
''',
    "coffeescript": '''# @MARKER@
marker = "@MARKER@"
items = [{name: "First", size: 42}]
describe = (item) ->
  "#{item.name}:#{item.size}"
summary = (describe item for item in items)
console.log marker, summary
''',
    "handlebars": '''<!-- @MARKER@ -->
<article data-marker="@MARKER@">
  <h1>{{title}}</h1>
  <ul>
    {{#items}}
    <li>{{name}}: {{size}}</li>
    {{/items}}
  </ul>
</article>
''',
    "haml": '''-# @MARKER@
%article{data: {marker: "@MARKER@"}}
  %h1 Preview fixture
  %ul
    - ["First", "Second"].each do |name|
      %li= name
  %p Structured Haml syntax
''',
    "erb": '''<%# @MARKER@ %>
<% items = ["First", "Second"] %>
<article data-marker="@MARKER@">
  <h1>Preview fixture</h1>
  <ul>
    <% items.each do |name| %>
      <li><%= name %></li>
    <% end %>
  </ul>
</article>
''',
    "vim": '''" @MARKER@
let g:coverage_marker = '@MARKER@'
function! CoverageDescribe(name, size) abort
  return a:name . ':' . a:size
endfunction
let s:items = ['First', 'Second']
for s:item in s:items
  echo CoverageDescribe(s:item, 42)
endfor
''',
    "http": '''# @MARKER@
GET https://example.invalid/preview HTTP/1.1
Accept: application/json
X-Coverage-Marker: @MARKER@

### A second HTTP request, never sent by the fixture generator
POST https://example.invalid/preview HTTP/1.1
Content-Type: application/json

{"name":"First","size":42}
''',
    "nginx": '''# @MARKER@
server {
    listen 8080;
    server_name localhost;
    location /preview {
        default_type text/plain;
        return 200 "@MARKER@";
    }
}
''',
}

# A suffix is sometimes a distinct grammar within a highlighter group. These
# are syntax examples, not just the group's default text renamed repeatedly.
VARIANTS = {
    ("ini", "desktop"): '''# @MARKER@
[Desktop Entry]
Type=Application
Name=@MARKER@
Comment=Preview-only desktop entry
Exec=echo preview
Terminal=false
Categories=Utility;
''',
    ("plain-config", "gitignore"): '''# @MARKER@
.build/
node_modules/
*.log
!keep.log
/cache/**
[Oo]utput/
''',
    ("plain-config", "gitattributes"): '''# @MARKER@
* text=auto
*.md text eol=lf
*.json text diff
*.png binary
*.sh text eol=lf
/fixtures/** linguist-generated=true
''',
    ("plain-config", "gitmodules"): '''# @MARKER@
[submodule "preview-fixture"]
    path = vendor/preview-fixture
    url = https://example.invalid/preview-fixture.git
    branch = main
    update = checkout
''',
    ("git-config", "editorconfig"): '''# @MARKER@
root = true
[*]
charset = utf-8
indent_style = space
indent_size = 2
end_of_line = lf
insert_final_newline = true
''',
    ("git-config", "npmrc"): '''# @MARKER@
coverage-marker=@MARKER@
registry=https://registry.npmjs.org/
save-exact=true
fund=false
audit=false
progress=false
''',
    ("git-config", "yarnrc"): '''# @MARKER@
registry "https://registry.yarnpkg.com"
user-agent "@MARKER@"
network-timeout 30000
save-prefix ""
ignore-scripts true
''',
    ("swift", "swiftinterface"): '''// swift-interface-format-version: 1.0
// @MARKER@
// A Swift interface syntax excerpt, not a serialized compiler product.
import Swift
public struct PreviewItem {
  public let name: Swift.String
  public let size: Swift.Int
}
public let coverageMarker: Swift.String
''',
    ("javascript", "jsx"): '''// @MARKER@
const marker = "@MARKER@";
const items = ["First", "Second"];
function Preview() {
  return <article data-marker={marker}>
    <h1>Preview fixture</h1>
    <ul>{items.map(name => <li key={name}>{name}</li>)}</ul>
  </article>;
}
''',
    ("typescript", "tsx"): '''// @MARKER@
const marker: string = "@MARKER@";
interface Item { name: string; size: number }
const items: Item[] = [{name: "First", size: 42}];
export function Preview() {
  return <article data-marker={marker}>
    {items.map(item => <p key={item.name}>{item.name}: {item.size}</p>)}
  </article>;
}
''',
    ("python", "pyi"): '''# @MARKER@
from typing import Final, Sequence
MARKER: Final[str]
class PreviewItem:
    name: str
    size: int
    def __init__(self, name: str, size: int) -> None: ...
def describe(items: Sequence[PreviewItem]) -> list[str]: ...
''',
    ("python", "pyx"): '''# @MARKER@
# Cython implementation syntax sample.
cdef str marker = "@MARKER@"
cdef int twice(int value):
    return value * 2
cpdef int preview_size(int size):
    return twice(size)
''',
    ("python", "pxd"): '''# @MARKER@
# Cython declaration syntax sample.
cdef struct PreviewItem:
    int size
    bint enabled
cdef int twice(int value)
cpdef int preview_size(int size)
''',
    ("fsharp", "fsi"): '''// @MARKER@
module CoverageFixture
type PreviewItem = { Name: string; Size: int }
val marker: string
val describe: PreviewItem -> string
val items: PreviewItem list
''',
    ("shell", "csh"): '''#!/bin/csh
# @MARKER@
set marker = '@MARKER@'
set items = (First Second)
echo "$marker"
foreach item ($items)
    echo "${item}:42"
end
''',
    ("shell", "fish"): '''#!/usr/bin/env fish
# @MARKER@
set marker '@MARKER@'
function describe --argument-names name size
    printf '%s:%s\\n' $name $size
end
for name in First Second
    describe $name 42
end
''',
    ("web-components", "vue"): '''<!-- @MARKER@ -->
<script setup>
const marker = "@MARKER@";
const items = ["First", "Second"];
</script>
<template>
  <article :data-marker="marker">
    <h1>{{ marker }}</h1>
    <p v-for="name in items" :key="name">{{ name }}</p>
  </article>
</template>
''',
    ("web-components", "astro"): '''---
const marker = "@MARKER@";
const items = ["First", "Second"];
---
<article data-marker={marker}>
  <h1>{marker}</h1>
  <ul>{items.map(name => <li>{name}</li>)}</ul>
</article>
''',
    ("hcl", "tf"): '''# @MARKER@
variable "coverage_marker" {
  type = string
  default = "@MARKER@"
}
locals {
  preview = { name = "First", size = 42 }
}
output "preview_name" { value = local.preview.name }
''',
    ("zig", "zon"): '''.{
    .marker = "@MARKER@",
    .name = "preview-fixture",
    .version = "1.0.0",
    .enabled = true,
    .items = .{ "First", "Second" },
}
''',
    ("erlang", "hrl"): '''%% @MARKER@
-ifndef(COVERAGE_FIXTURE_HRL).
-define(COVERAGE_FIXTURE_HRL, true).
-define(COVERAGE_MARKER, "@MARKER@").
-record(preview_item, {name = "First", size = 42}).
-type preview_size() :: non_neg_integer().
-endif.
''',
    ("haskell", "lhs"): '''@MARKER@
A Bird-style literate Haskell syntax sample.

> module CoverageFixture where
> marker :: String
> marker = "@MARKER@"
> describe :: String -> Int -> String
> describe name size = name ++ ":" ++ show size
''',
    ("clojure", "edn"): ''';; @MARKER@
{:coverage-marker "@MARKER@"
 :enabled true
 :items [{:name "First" :size 42}
         {:name "Second" :size 84}]
 :tags #{:preview :text}
 :options {:limit 10 :empty nil}}
''',
    ("lisp", "el"): ''';;; @MARKER@
(defconst coverage-marker "@MARKER@")
(defun coverage-describe (name size)
  "Describe a preview item."
  (format "%s:%d" name size))
(defvar coverage-items '(("First" 42) ("Second" 84)))
(provide 'coverage-fixture)
''',
    ("scheme", "rkt"): '''#lang racket
;; @MARKER@
(define coverage-marker "@MARKER@")
(struct preview-item (name size) #:transparent)
(define (describe item)
  (format "~a:~a" (preview-item-name item) (preview-item-size item)))
(define items (list (preview-item "First" 42)))
(provide coverage-marker describe)
''',
    ("ocaml", "mli"): '''(* @MARKER@ *)
(** OCaml interface syntax sample. *)
type preview_item = { name : string; size : int }
val marker : string
val describe : preview_item -> string
val items : preview_item list
''',
    ("assembly", "s"): '''# @MARKER@
.section .rodata
coverage_marker:
    .asciz "@MARKER@"
.text
.globl coverage_add
coverage_add:
    movl %edi, %eax
    addl %esi, %eax
    ret
''',
    ("powershell", "psd1"): '''# @MARKER@
@{
    RootModule = 'CoverageFixture.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b372d3bb-316e-4237-815a-270e80315685'
    Author = 'Preview Fixture'
    Description = '@MARKER@'
    FunctionsToExport = @('Get-PreviewDescription')
}
''',
    ("latex", "sty"): '''% @MARKER@
\\NeedsTeXFormat{LaTeX2e}
\\ProvidesPackage{coveragefixture}[2026/11/11 preview syntax]
\\newcommand{\\coveragemarker}{\\detokenize{@MARKER@}}
\\newenvironment{previewitems}{\\begin{itemize}}{\\end{itemize}}
\\newcommand{\\previewitem}[1]{\\item #1}
\\endinput
''',
    ("latex", "cls"): '''% @MARKER@
\\NeedsTeXFormat{LaTeX2e}
\\ProvidesClass{coveragefixture}[2026/11/11 preview syntax]
\\LoadClass{article}
\\newcommand{\\coveragemarker}{\\detokenize{@MARKER@}}
\\newcommand{\\previewtitle}[1]{\\section{#1}}
\\endinput
''',
    ("shader", "vert"): '''#version 330 core
// @MARKER@
layout(location = 0) in vec3 position;
uniform mat4 modelViewProjection;
void main() {
    gl_Position = modelViewProjection * vec4(position, 1.0);
}
''',
    ("shader", "geom"): '''#version 330 core
// @MARKER@
layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;
void main() {
    for (int i = 0; i < 3; ++i) {
        gl_Position = gl_in[i].gl_Position;
        EmitVertex();
    }
    EndPrimitive();
}
''',
    ("shader", "tesc"): '''#version 400 core
// @MARKER@
layout(vertices = 3) out;
void main() {
    gl_out[gl_InvocationID].gl_Position = gl_in[gl_InvocationID].gl_Position;
    gl_TessLevelInner[0] = 1.0;
    gl_TessLevelOuter[0] = 1.0;
    gl_TessLevelOuter[1] = 1.0;
    gl_TessLevelOuter[2] = 1.0;
}
''',
    ("shader", "tese"): '''#version 400 core
// @MARKER@
layout(triangles, equal_spacing, cw) in;
void main() {
    gl_Position = gl_TessCoord.x * gl_in[0].gl_Position
        + gl_TessCoord.y * gl_in[1].gl_Position
        + gl_TessCoord.z * gl_in[2].gl_Position;
}
''',
    ("shader", "comp"): '''#version 430 core
// @MARKER@
layout(local_size_x = 1) in;
layout(std430, binding = 0) buffer Values { uint values[]; };
void main() {
    uint index = gl_GlobalInvocationID.x;
    values[index] += 1u;
}
''',
    ("nim", "nimble"): '''# @MARKER@
version = "1.0.0"
author = "Preview Fixture"
description = "@MARKER@"
license = "MIT"
srcDir = "src"
requires "nim >= 2.0.0"
''',
    ("coffeescript", "litcoffee"): '''@MARKER@
A literate CoffeeScript syntax sample.

    marker = "@MARKER@"
    items = [{name: "First", size: 42}]
    describe = (item) -> "#{item.name}:#{item.size}"
    summary = (describe item for item in items)
''',
}

XML_VARIANTS = {
    "xsd": '''<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <!-- @MARKER@ -->
  <xs:element name="preview">
    <xs:complexType><xs:sequence>
      <xs:element name="name" type="xs:string"/>
      <xs:element name="size" type="xs:integer"/>
    </xs:sequence></xs:complexType>
  </xs:element>
</xs:schema>
''',
    "xsl": '''<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <!-- @MARKER@ -->
  <xsl:output method="html"/>
  <xsl:template match="/">
    <article><h1>@MARKER@</h1>
      <xsl:for-each select="preview/items/item"><p><xsl:value-of select="."/></p></xsl:for-each>
    </article>
  </xsl:template>
</xsl:stylesheet>
''',
    "xib": '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<document type="com.apple.InterfaceBuilder3.Cocoa.XIB" version="3.0" targetRuntime="MacOSX.Cocoa">
  <objects>
    <customObject id="-2" userLabel="File's Owner" customClass="NSObject"/>
    <customObject id="-1" userLabel="First Responder" customClass="FirstResponder"/>
    <customObject id="-3" userLabel="@MARKER@" customClass="NSObject"/>
  </objects>
</document>
''',
    "storyboard": '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<document type="com.apple.InterfaceBuilder3.Cocoa.Storyboard.XIB" version="3.0" targetRuntime="MacOSX.Cocoa">
  <scenes><scene sceneID="fixture-scene"><objects>
    <viewController id="fixture-controller" sceneMemberID="viewController">
      <view key="view" id="fixture-view" userLabel="@MARKER@"/>
    </viewController>
  </objects></scene></scenes>
</document>
''',
    "wsdl": '''<definitions xmlns="http://schemas.xmlsoap.org/wsdl/" xmlns:tns="urn:coverage" targetNamespace="urn:coverage">
  <!-- @MARKER@ -->
  <documentation>@MARKER@</documentation>
  <message name="PreviewRequest"/>
  <message name="PreviewResponse"/>
  <portType name="PreviewPort"><operation name="Preview">
    <input message="tns:PreviewRequest"/><output message="tns:PreviewResponse"/>
  </operation></portType>
</definitions>
''',
    "pom": '''<project xmlns="http://maven.apache.org/POM/4.0.0">
  <!-- @MARKER@ -->
  <modelVersion>4.0.0</modelVersion>
  <groupId>example.preview</groupId>
  <artifactId>coverage-fixture</artifactId>
  <version>1.0.0</version>
  <name>@MARKER@</name>
</project>
''',
    "resx": '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<root>
  <resheader name="resmimetype"><value>text/microsoft-resx</value></resheader>
  <resheader name="version"><value>2.0</value></resheader>
  <data name="CoverageMarker" xml:space="preserve"><value>@MARKER@</value></data>
  <data name="PreviewTitle" xml:space="preserve"><value>Preview fixture</value></data>
</root>
''',
    "csproj": '''<Project Sdk="Microsoft.NET.Sdk">
  <!-- @MARKER@ -->
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <CoverageMarker>@MARKER@</CoverageMarker>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
''',
    "props": '''<Project>
  <!-- @MARKER@ -->
  <PropertyGroup>
    <CoverageMarker>@MARKER@</CoverageMarker>
    <PreviewEnabled>true</PreviewEnabled>
    <PreviewLimit>10</PreviewLimit>
  </PropertyGroup>
</Project>
''',
    "targets": '''<Project>
  <!-- @MARKER@ -->
  <Target Name="PreviewFixture">
    <Message Text="@MARKER@" Importance="high"/>
    <ItemGroup><PreviewItem Include="First;Second"/></ItemGroup>
  </Target>
</Project>
''',
}
XML_VARIANTS["xslt"] = XML_VARIANTS["xsl"]
VARIANTS.update({("xml", extension): text for extension, text in XML_VARIANTS.items()})
VARIANTS[("verilog", "vh")] = VARIANTS[("verilog", "svh")] = '''// @MARKER@
`ifndef COVERAGE_FIXTURE_VH
`define COVERAGE_FIXTURE_VH
`define COVERAGE_MARKER "@MARKER@"
`define PREVIEW_SIZE 42
`define PREVIEW_ENABLED 1
`endif
'''
VARIANTS[("plist", "entitlements")] = '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><false/>
</dict></plist>
'''
VARIANTS[("plist", "mobileconfig")] = '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<plist version="1.0"><dict>
  <key>PayloadDisplayName</key><string>@MARKER@</string>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadIdentifier</key><string>example.preview.coverage</string>
  <key>PayloadUUID</key><string>D9E3A270-EBB6-4BD9-B60E-88C5B7156BB4</string>
  <key>PayloadContent</key><array/>
</dict></plist>
'''
VARIANTS[("plist", "stringsdict")] = '''<?xml version="1.0" encoding="UTF-8"?>
<!-- @MARKER@ -->
<plist version="1.0"><dict><key>@MARKER@</key><dict>
  <key>NSStringLocalizedFormatKey</key><string>%#@items@</string>
  <key>items</key><dict>
    <key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>
    <key>NSStringFormatValueTypeKey</key><string>d</string>
    <key>one</key><string>One item</string>
    <key>other</key><string>%d items</string>
  </dict>
</dict></dict></plist>
'''


def coverage_marker(group, extension):
    return "QLCOVERAGE_" + group.upper().replace("-", "_") + "_" + extension.upper().replace("+", "_PLUS")


def fixture_text(group, extension, marker):
    key = (group, extension)
    text = VARIANTS.get(key, TEMPLATES[group])
    if PLACEHOLDER not in text:
        raise ValueError(f"Template lacks marker: {key}")
    return text.replace(PLACEHOLDER, marker), f"{group}/{extension}" if key in VARIANTS else group


def generate(output=DEFAULT_OUTPUT, source=SOURCE):
    output = Path(output).resolve()
    source = Path(source).resolve()
    source_bytes = source.read_bytes()
    groups = json.loads(source_bytes)
    expected_groups = {group["id"] for group in groups}
    if set(TEMPLATES) != expected_groups:
        raise ValueError(f"Template groups differ from manifest: {set(TEMPLATES) ^ expected_groups}")
    declared = [(group, extension) for group in groups for extension in group["extensions"]]
    extensions = [extension for _, extension in declared]
    if len(extensions) != len(set(extensions)):
        raise ValueError("Source manifest contains duplicate suffixes")
    files = output / "files"
    files.mkdir(parents=True, exist_ok=True)
    cases = []
    for group, extension in declared:
        marker = coverage_marker(group["id"], extension)
        text, template_id = fixture_text(group["id"], extension, marker)
        if marker not in "\n".join(text.splitlines()[:3]):
            raise ValueError(f"Marker must appear within first three lines: {template_id}")
        file_name = f"coverage-{group['id']}.{extension}"
        path = files / file_name
        if path.is_symlink():
            raise ValueError(f"Refusing to replace a symlink: {path}")
        data = text.encode("utf-8")
        path.write_bytes(data)
        cases.append({
            "id": f"{group['id']}.{extension}",
            "extension": extension,
            "fileName": file_name,
            "path": str(path),
            "formatGroup": group["id"],
            "expectedMode": group["mode"],
            "marker": marker,
            "sha256": hashlib.sha256(data).hexdigest(),
            "language": group["language"],
            "templateID": template_id,
            "syntaxNote": "Representative text syntax; preview only, not a complete project or runtime/compiler validation.",
        })
    report = {
        "schemaVersion": 1,
        "sourceManifest": str(source.relative_to(ROOT)) if source.is_relative_to(ROOT) else str(source),
        "sourceManifestSHA256": hashlib.sha256(source_bytes).hexdigest(),
        "fixtureNature": "Representative text syntax samples; never executed or installed as configuration.",
        "caseCount": len(cases),
        "groupCount": len(groups),
        "coveredGroupCount": len({case["formatGroup"] for case in cases}),
        "filenameOnlyGroups": [group["id"] for group in groups if not group["extensions"]],
        "cases": cases,
    }
    (output / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "extensions.txt").write_text("\n".join(extensions) + "\n", encoding="utf-8")
    compact_cases = [{key: case[key] for key in ("fileName", "marker", "extension")} for case in cases]
    (output / "cua-cases.json").write_text(json.dumps(compact_cases, separators=(",", ":")) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    report = generate(args.output)
    print(f"Generated {report['caseCount']} suffix cases across {report['coveredGroupCount']} suffix-bearing groups.")
    print(f"Manifest: {args.output.resolve() / 'manifest.json'}")
    print(f"CUA cases: {args.output.resolve() / 'cua-cases.json'}")


if __name__ == "__main__":
    main()
