//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// A simple XML tree used to serialize Mapnik XML (mirroring carto's
/// `util.jsonToXML` object shape: `_name`, `_attributes`, `_content`).
enum XMLNode {

    struct Element {
        var name: String
        var attributes: [String: String]
        /// Child elements (when not text content).
        var children: [XMLNode]
        /// Text content (CDATA-serialized when `cdata` is set).
        var content: String?
        var cdata: Bool

        init(
            name: String,
            attributes: [String: String] = [:],
            children: [XMLNode] = [],
            content: String? = nil,
            cdata: Bool = false,
        ) {
            self.name = name
            self.attributes = attributes
            self.children = children
            self.content = content
            self.cdata = cdata
        }
    }

    case element(Element)

    static func element(_ name: String, attributes: [String: String] = [:]) -> Element {
        Element(name: name, attributes: attributes)
    }

    static func element(_ name: String, content: [XMLNode]) -> Element {
        Element(name: name, children: content)
    }

    static func element(_ name: String, content: String) -> Element {
        Element(name: name, content: content, cdata: false)
    }

}

/// Serialize an XML tree with carto's exact whitespace/CDATA rules
/// (`util.jsonToXML`).
enum XMLSerializer {

    static func serialize(_ element: XMLNode.Element) -> String {
        var output = ""
        write(element, to: &output, level: 0)
        return output
    }

    static func write(_ element: XMLNode.Element, to output: inout String, level: Int) {
        let indent: String = .init(repeating: "  ", count: level)

        output += indent + "<" + element.name

        if !element.attributes.isEmpty {
            for key in element.attributes.keys.sorted() {
                output += " \(key)=\"\(element.attributes[key]!)\""
            }
        }

        if element.children.isEmpty, element.content == nil {
            output += " />\n"
            return
        }

        if !element.children.isEmpty {
            output += ">\n"
            for child in element.children {
                switch child {
                case let .element(childElement):
                    write(childElement, to: &output, level: level + 1)
                }
            }
            output += indent + "</" + element.name + ">\n"
            return
        }

        // Text content. carto's jsonToXML: the content is serialized first
        // (CDATA for strings), and the multiline check runs on the serialized
        // form (subtag detection).
        if let content = element.content {
            let serialized = element.cdata ? "<![CDATA[\(content)]]>" : content
            if serialized.contains("</") || serialized.contains("/>") {
                output += ">\n" + serialized
                output += indent + "</" + element.name + ">\n"
            }
            else {
                output += ">" + serialized + "</" + element.name + ">\n"
            }
            return
        }

        output += " />\n"
    }

}
