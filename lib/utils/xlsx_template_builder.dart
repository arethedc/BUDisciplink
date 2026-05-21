import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List buildStudentImportTemplateXlsx() {
  final archive = Archive();

  void addTextFile(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addTextFile('[Content_Types].xml', _contentTypesXml);
  addTextFile('_rels/.rels', _rootRelsXml);
  addTextFile('docProps/app.xml', _appXml);
  addTextFile('docProps/core.xml', _coreXml);
  addTextFile('xl/workbook.xml', _workbookXml);
  addTextFile('xl/_rels/workbook.xml.rels', _workbookRelsXml);
  addTextFile('xl/styles.xml', _stylesXml);
  addTextFile('xl/worksheets/sheet1.xml', _sheetXml);

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _contentTypesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
''';

const _rootRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
''';

const _appXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>BUDiscipLink</Application>
</Properties>
''';

String get _coreXml {
  final now = DateTime.now().toUtc().toIso8601String();
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>BUDiscipLink Student Accounts Import Template</dc:title>
  <dc:creator>BUDiscipLink</dc:creator>
  <cp:lastModifiedBy>BUDiscipLink</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>
''';
}

const _workbookXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Student Import" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
''';

const _workbookRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
''';

const _stylesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><color rgb="FF1F2A1F"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF1B5E20"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD9E2D4"/></left>
      <right style="thin"><color rgb="FFD9E2D4"/></right>
      <top style="thin"><color rgb="FFD9E2D4"/></top>
      <bottom style="thin"><color rgb="FFD9E2D4"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="49" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyNumberFormat="1">
      <alignment horizontal="center" vertical="center"/>
    </xf>
    <xf numFmtId="49" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyNumberFormat="1">
      <alignment vertical="center"/>
    </xf>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="Normal" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>
''';

const _sheetXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheetViews>
    <sheetView workbookViewId="0">
      <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
      <selection pane="bottomLeft" activeCell="A2" sqref="A2"/>
    </sheetView>
  </sheetViews>
  <cols>
    <col min="1" max="1" width="18" customWidth="1"/>
    <col min="2" max="2" width="42" customWidth="1"/>
    <col min="3" max="3" width="18" customWidth="1"/>
    <col min="4" max="4" width="38" customWidth="1"/>
  </cols>
  <sheetData>
    <row r="1" ht="24" customHeight="1">
      <c r="A1" t="inlineStr" s="1"><is><t>Student Number</t></is></c>
      <c r="B1" t="inlineStr" s="1"><is><t>Student Name</t></is></c>
      <c r="C1" t="inlineStr" s="1"><is><t>Program Code</t></is></c>
      <c r="D1" t="inlineStr" s="1"><is><t>Email Address</t></is></c>
    </row>
    <row r="2">
      <c r="A2" s="2"/>
      <c r="B2" s="2"/>
      <c r="C2" s="2"/>
      <c r="D2" s="2"/>
    </row>
  </sheetData>
  <dataValidations count="3">
    <dataValidation type="textLength" operator="equal" allowBlank="1" showErrorMessage="1" sqref="A2:A1000" errorTitle="Invalid Student Number" error="Use the format 231-0996." promptTitle="Student Number" prompt="Use the format 231-0996." showInputMessage="1">
      <formula1>8</formula1>
    </dataValidation>
    <dataValidation type="custom" allowBlank="1" showErrorMessage="0" sqref="B2:B1000" promptTitle="Student Name" prompt="Preferred: LAST NAME, First Name, Middle Name, Suffix. If no middle name but with suffix, use: LAST NAME, First Name, II." showInputMessage="1">
      <formula1>LEN(B2)&gt;0</formula1>
    </dataValidation>
    <dataValidation type="custom" allowBlank="1" showErrorMessage="1" sqref="D2:D1000" errorTitle="Invalid Email" error="Enter a valid email address." promptTitle="Email Address" prompt="Example: student@baliuagu.edu.ph" showInputMessage="1">
      <formula1>ISNUMBER(SEARCH(&quot;@&quot;,D2))</formula1>
    </dataValidation>
  </dataValidations>
</worksheet>
''';
