"""Common Spider HTML helpers; XPath uses elementpath, HTML uses html5lib.

This implements frequently used lxml/PyQuery surfaces, not their native C API.
Unsupported methods raise normal Python errors rather than fabricating results.
"""
import sys
import types
import xml.etree.ElementTree as ET

import elementpath
import html5lib
from bs4 import BeautifulSoup, Tag


class Element:
    def __init__(self, node, root=None):
        self.node = node
        self.root = root if root is not None else node

    @property
    def tag(self):
        return self.node.tag

    @property
    def text(self):
        return self.node.text

    @text.setter
    def text(self, value):
        self.node.text = value

    @property
    def tail(self):
        return self.node.tail

    @property
    def attrib(self):
        return self.node.attrib

    def get(self, name, default=None):
        return self.node.get(name, default)

    def set(self, name, value):
        self.node.set(name, value)

    def xpath(self, path, namespaces=None, **variables):
        variables.pop("smart_strings", None)
        result = elementpath.select(self.root, path, item=self.node,
            parser=elementpath.XPath1Parser, namespaces=namespaces, variables=variables)
        def wrapped(value):
            return Element(value, self.root) if ET.iselement(value) else value
        return [wrapped(x) for x in result] if isinstance(result, list) else wrapped(result)

    def itertext(self):
        return self.node.itertext()

    def text_content(self):
        return "".join(self.node.itertext())

    def find(self, path, namespaces=None):
        value = self.node.find(path, namespaces)
        return Element(value, self.root) if value is not None else None

    def findall(self, path, namespaces=None):
        return [Element(node, self.root) for node in self.node.findall(path, namespaces)]

    def getparent(self):
        for parent in self.root.iter():
            if self.node in list(parent):
                return Element(parent, self.root)
        return None

    def getnext(self):
        parent = self.getparent()
        if parent is None:
            return None
        children = list(parent.node)
        index = children.index(self.node) + 1
        return Element(children[index], self.root) if index < len(children) else None

    def __iter__(self):
        return (Element(child, self.root) for child in self.node)

    def __getitem__(self, key):
        value = self.node[key]
        return [Element(x, self.root) for x in value] if isinstance(value, list) else Element(value, self.root)

    def __len__(self):
        return len(self.node)

    def __str__(self):
        return tostring(self, encoding="unicode")


def HTML(value, parser=None, **kwargs):
    return Element(html5lib.parse(value or "", treebuilder="etree", namespaceHTMLElements=False))


def XML(value, parser=None, **kwargs):
    return Element(ET.fromstring(value))


def fromstring(value, parser=None, **kwargs):
    fragment = html5lib.parseFragment(value, treebuilder="etree", namespaceHTMLElements=False)
    if len(fragment) == 1:
        return Element(fragment[0])
    fragment.tag = "div"
    return Element(fragment)


def tostring(value, encoding="utf-8", method="html", **kwargs):
    return ET.tostring(value.node if isinstance(value, Element) else value, encoding=encoding, method=method)


class PyQuery:
    def __init__(self, value="", **kwargs):
        if isinstance(value, PyQuery):
            self.nodes = value.nodes[:]
        elif isinstance(value, Tag):
            self.nodes = [value]
        elif isinstance(value, list):
            self.nodes = value
        else:
            self.nodes = [BeautifulSoup(str(value), "html.parser")]

    def __call__(self, selector):
        return self.find(selector)

    def find(self, selector):
        return PyQuery([match for node in self.nodes for match in node.select(selector)])

    def eq(self, index):
        return PyQuery([self.nodes[index]]) if -len(self.nodes) <= index < len(self.nodes) else PyQuery([])

    def items(self, selector=None):
        nodes = self.find(selector).nodes if selector else self.nodes
        return (PyQuery(node) for node in nodes)

    def attr(self, name, value=None):
        if value is not None:
            for node in self.nodes:
                node[name] = value
            return self
        if not self.nodes:
            return None
        result = self.nodes[0].get(name)
        return " ".join(result) if isinstance(result, list) else result

    def text(self):
        return " ".join(node.get_text(" ", strip=True) for node in self.nodes)

    def html(self):
        return self.nodes[0].decode_contents() if self.nodes else None

    def outer_html(self):
        return str(self.nodes[0]) if self.nodes else ""

    def parent(self):
        return PyQuery([node.parent for node in self.nodes if node.parent is not None])

    def children(self, selector=None):
        return PyQuery([child for node in self.nodes for child in node.find_all(selector, recursive=False)])

    def remove(self):
        for node in self.nodes:
            node.decompose()
        return self

    @property
    def length(self):
        return len(self.nodes)

    def __len__(self):
        return len(self.nodes)

    def __bool__(self):
        return bool(self.nodes)

    def __iter__(self):
        return iter(self.nodes)

    def __getitem__(self, key):
        return self.nodes[key]


def install():
    lxml = types.ModuleType("lxml")
    lxml.__path__ = []
    etree = types.ModuleType("lxml.etree")
    etree.HTML, etree.XML, etree.fromstring, etree.tostring = HTML, XML, XML, tostring
    etree._Element = Element
    etree.Element = lambda tag, attrib=None, **extra: Element(ET.Element(tag, attrib or {}, **extra))
    etree.HTMLParser = lambda **kwargs: None
    etree.XMLParser = lambda **kwargs: None
    etree.XMLSyntaxError, etree.XPathError = ET.ParseError, elementpath.ElementPathError
    html = types.ModuleType("lxml.html")
    html.fromstring, html.tostring = fromstring, tostring
    pyquery = types.ModuleType("pyquery")
    pyquery.PyQuery = PyQuery
    lxml.etree, lxml.html = etree, html
    for module in (lxml, etree, html, pyquery):
        sys.modules[module.__name__] = module
