import hljs from "highlight.js/lib/core";
import asciidoc from "highlight.js/lib/languages/asciidoc";
import avrasm from "highlight.js/lib/languages/avrasm";
import awk from "highlight.js/lib/languages/awk";
import bash from "highlight.js/lib/languages/bash";
import c from "highlight.js/lib/languages/c";
import clojure from "highlight.js/lib/languages/clojure";
import cmake from "highlight.js/lib/languages/cmake";
import coffeescript from "highlight.js/lib/languages/coffeescript";
import cpp from "highlight.js/lib/languages/cpp";
import csharp from "highlight.js/lib/languages/csharp";
import css from "highlight.js/lib/languages/css";
import d from "highlight.js/lib/languages/d";
import dart from "highlight.js/lib/languages/dart";
import diff from "highlight.js/lib/languages/diff";
import dockerfile from "highlight.js/lib/languages/dockerfile";
import dos from "highlight.js/lib/languages/dos";
import elixir from "highlight.js/lib/languages/elixir";
import erlang from "highlight.js/lib/languages/erlang";
import fsharp from "highlight.js/lib/languages/fsharp";
import glsl from "highlight.js/lib/languages/glsl";
import go from "highlight.js/lib/languages/go";
import graphql from "highlight.js/lib/languages/graphql";
import groovy from "highlight.js/lib/languages/groovy";
import haml from "highlight.js/lib/languages/haml";
import handlebars from "highlight.js/lib/languages/handlebars";
import haskell from "highlight.js/lib/languages/haskell";
import http from "highlight.js/lib/languages/http";
import ini from "highlight.js/lib/languages/ini";
import java from "highlight.js/lib/languages/java";
import javascript from "highlight.js/lib/languages/javascript";
import json from "highlight.js/lib/languages/json";
import julia from "highlight.js/lib/languages/julia";
import kotlin from "highlight.js/lib/languages/kotlin";
import latex from "highlight.js/lib/languages/latex";
import less from "highlight.js/lib/languages/less";
import lisp from "highlight.js/lib/languages/lisp";
import lua from "highlight.js/lib/languages/lua";
import makefile from "highlight.js/lib/languages/makefile";
import markdown from "highlight.js/lib/languages/markdown";
import nginx from "highlight.js/lib/languages/nginx";
import nim from "highlight.js/lib/languages/nim";
import objectivec from "highlight.js/lib/languages/objectivec";
import ocaml from "highlight.js/lib/languages/ocaml";
import perl from "highlight.js/lib/languages/perl";
import php from "highlight.js/lib/languages/php";
import plaintext from "highlight.js/lib/languages/plaintext";
import powershell from "highlight.js/lib/languages/powershell";
import properties from "highlight.js/lib/languages/properties";
import protobuf from "highlight.js/lib/languages/protobuf";
import python from "highlight.js/lib/languages/python";
import r from "highlight.js/lib/languages/r";
import ruby from "highlight.js/lib/languages/ruby";
import rust from "highlight.js/lib/languages/rust";
import scala from "highlight.js/lib/languages/scala";
import scheme from "highlight.js/lib/languages/scheme";
import scss from "highlight.js/lib/languages/scss";
import shell from "highlight.js/lib/languages/shell";
import sql from "highlight.js/lib/languages/sql";
import swift from "highlight.js/lib/languages/swift";
import tcl from "highlight.js/lib/languages/tcl";
import typescript from "highlight.js/lib/languages/typescript";
import vbnet from "highlight.js/lib/languages/vbnet";
import vbscript from "highlight.js/lib/languages/vbscript";
import verilog from "highlight.js/lib/languages/verilog";
import vhdl from "highlight.js/lib/languages/vhdl";
import vim from "highlight.js/lib/languages/vim";
import wasm from "highlight.js/lib/languages/wasm";
import x86asm from "highlight.js/lib/languages/x86asm";
import xml from "highlight.js/lib/languages/xml";
import yaml from "highlight.js/lib/languages/yaml";

const languages = {
  asciidoc, avrasm, awk, bash, c, clojure, cmake, coffeescript, cpp, csharp, css,
  d, dart, diff, dockerfile, dos, elixir, erlang, fsharp, glsl, go, graphql, groovy,
  haml, handlebars, haskell, http, ini, java, javascript, json, julia, kotlin,
  latex, less, lisp, lua, makefile, markdown, nginx, nim, objectivec, ocaml,
  perl, php, plaintext, powershell, properties, protobuf, python, r, ruby, rust,
  scala, scheme, scss, shell, sql, swift, tcl, typescript, vbnet, vbscript,
  verilog, vhdl, vim, wasm, x86asm, xml, yaml,
};
for (const [name, definition] of Object.entries(languages)) hljs.registerLanguage(name, definition);
hljs.registerAliases(["toml"], { languageName: "ini" });
hljs.registerAliases(["html", "xhtml", "svg"], { languageName: "xml" });
hljs.registerAliases(["text", "log", "jsonl", "ndjson"], { languageName: "plaintext" });
hljs.registerAliases(["erb"], { languageName: "ruby" });

export function languageName(value) {
  const language = String(value || "plaintext").toLowerCase();
  return hljs.getLanguage(language) ? language : "plaintext";
}

export function highlight(content, language) {
  return hljs.highlight(content, { language: languageName(language), ignoreIllegals: true }).value;
}

export const supportedLanguages = Object.freeze([...Object.keys(languages), "toml", "html", "erb"]);
