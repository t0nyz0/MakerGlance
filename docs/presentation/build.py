#!/usr/bin/env python3
"""Build editable slides and a tagged, selectable-text PDF from approved demo media."""
from datetime import datetime, timezone
from pathlib import Path
import tempfile
from PIL import Image
from pptx import Presentation
from pptx.util import Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, BooleanObject, DictionaryObject, NameObject, NumberObject, TextStringObject

ROOT = Path(__file__).resolve().parent
MEDIA = ROOT.parent / "media"
W, H = 960, 540
BG, PANEL, WHITE, MUTED, BLUE, VIOLET = "1B1C1F", "28292D", "F7F8FC", "CED1DC", "E6C64D", "B5A4FF"
FONT = Path("/System/Library/Fonts/Supplemental/Arial.ttf")
BOLD = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
if not FONT.exists():
    FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    BOLD = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
pdfmetrics.registerFont(TTFont("Deck", str(FONT)))
pdfmetrics.registerFont(TTFont("DeckBold", str(BOLD)))

def wrap(text, width, size, bold=False):
    font = "DeckBold" if bold else "Deck"
    result = []
    for para in text.split("\n"):
        line = ""
        for word in para.split():
            candidate = (line + " " + word).strip()
            if line and pdfmetrics.stringWidth(candidate, font, size) > width:
                result.append(line); line = word
            else: line = candidate
        result.append(line)
    return "\n".join(result)

class Slide:
    def __init__(self, section, title=None):
        self.items = []
        self.text("MAKERGLANCE / " + section.upper(), 36, 22, 870, 13, 10, BLUE, tag="P")
        if title: self.text(title, 36, 67, 890, 90, 36, WHITE, True, "H1")
    def text(self, value, x, y, w, h, size=18, color=MUTED, bold=False, tag="P"):
        value = wrap(value, w, size, bold)
        if len(value.splitlines()) * size * 1.18 > h + 2:
            raise ValueError("Text does not fit: " + value[:70])
        self.items.append(dict(kind="text", value=value, x=x,y=y,w=w,h=h,size=size,color=color,bold=bold,tag=tag))
    def rect(self, x,y,w,h,color=PANEL): self.items.append(dict(kind="rect",x=x,y=y,w=w,h=h,color=color))
    def image(self, name,x,y,w,h,alt,region=None):
        path = MEDIA / name
        with Image.open(path) as image: iw,ih=image.size
        rx,ry,rw,rh = region or (0,0,iw,ih)
        scale=min(w/rw,h/rh)
        self.items.append(dict(kind="image",path=path,x=x+(w-rw*scale)/2,y=y+(h-rh*scale)/2,w=rw*scale,h=rh*scale,iw=iw,ih=ih,region=(rx,ry,rw,rh),alt=alt))

slides=[]
s=Slide("Creator analytics")
s.image("icon.png",36,65,58,58,"Original MakerGlance app icon")
s.text("See what moved.\nKeep the history.",36,147,355,115,39,WHITE,True,"H1")
s.text("Your MakerWorld creator workspace, at home on the Mac.",36,281,340,78,20)
s.text("Local observations. Clear comparisons.\nMore time for making.",36,388,345,65,17,BLUE)
s.image("print-check-poster.png",453,60,471,444,"Readable native fictional model card showing violet print growth and a separate blue latest-check NEW marker, with explanatory demo captions.",region=(0,86,440,660))
slides.append(s)

s=Slide("The workflow","Make the next check useful.")
s.text("Move from changing totals to a repeatable creator workflow.",36,147,880,35,20)
for index,(title,body) in enumerate([
    ("Observe","Keep local snapshots of your profile and watched models."),
    ("Compare","Separate the latest successful check from the growth in your chosen window."),
    ("Prioritize","Bring actual model changes to the front, then return to making.")]):
    x=36+index*300;s.rect(x,212,282,232)
    s.text(f"0{index+1}",x+18,231,240,50,32,BLUE,True)
    s.text(title,x+18,291,240,35,23,WHITE,True,"H2")
    s.text(body,x+18,339,243,94,17)
s.text("Profile totals and some reports overlap with MakerWorld. MakerGlance brings local history, monitoring choices and native desktop actions together.",36,464,875,37,13)
slides.append(s)

s=Slide("Prints & latest check","Put print growth in the spotlight.")
s.image("print-check-poster.png",36,157,315,320,"Fictional model card with violet print growth, a separate blue NEW marker and lifetime/Today metric rows.",region=(0,86,440,660))
s.text("Two useful signals.",389,162,530,40,25,WHITE,True,"H2")
s.rect(389,222,110,29,"4B328A");s.text("PRINTS",401,228,92,20,12,WHITE,True)
s.text("The selected window's print increase. A printer symbol and signed value reinforce the color.",389,269,510,70,18)
s.rect(389,355,67,27,"1D456C");s.text("NEW",401,360,45,20,12,WHITE,True)
s.text("An increase in the latest successful comparable check. The period total remains separate.",389,396,510,70,18)
slides.append(s)

s=Slide("Cards / Compact","One watchlist. Two ways to see it.")
s.image("cards-compact-poster.png",36,170,560,250,"Native Compact watched-model section, with all metric rows and original fictional model illustrations.",region=(0,86,790,460))
s.text("Same observations.\nYour preferred density.",630,175,290,92,25,WHITE,True,"H2")
s.text("Sort by prints, saves, boosts, downloads or likes. Choose lifetime totals or gains in your selected window.",630,290,285,145,19)
s.text("Cards or Compact. All observations preserved.",36,447,880,32,19,WHITE,True,"H2")

s.text("Same observations, selection and activity order. Persistent view choice. Text size from 85–150%.",36,486,880,22,13)
slides.append(s)

s=Slide("Your timeline","Your observations become a timeline.")
s.image("history-range-poster.png",36,154,888,248,"Native local history mosaic showing fictional metrics on independent scales with one shared date range.",region=(0,86,790,330))
for x,title,body in [(36,"Today","Local calendar midnight to midnight, with explicit observation coverage."),(340,"Rolling windows","24 hours and 7 days show observed changes in the selected period."),(644,"Server reports","Available Creator Center reports keep their UTC dates separate.")]:
    s.text(title,x,421,268,29,19,BLUE,True,"H2");s.text(body,x,458,269,48,13)
slides.append(s)

s=Slide("Community","Remember first seen. Keep dates honest.")
s.image("followers-focused.png",36,154,888,230,"Native fictional follower table showing first-observed new accounts and an unknown baseline follower date.",region=(0,535,2100,530))
for x,title,body in [(36,"Baseline","Existing follower dates stay unknown."),(340,"First observed","New accounts get a local observation time."),(644,"Search & sort","Bring order to the community list.")]:
    s.text(title,x,410,270,29,19,BLUE,True,"H2");s.text(body,x,451,270,45,15)
s.text("First observed is never presented as the original follow-relationship date.",36,500,875,20,12)
slides.append(s)

s=Slide("Desktop workflow","Your studio, a menu-bar click away.")
for y,title,body in [(163,"Scan unread activity","See Today changes and recent updates."),(269,"Jump back into a model","Refresh, open details or return to the dashboard."),(375,"Keep the window closed","Monitoring continues while the app is running.")]:
    s.rect(36,y,492,91);s.text(title,51,y+13,459,30,21,WHITE,True,"H2");s.text(body,51,y+51,459,28,15)
s.image("menu-dark.png",611,145,263,339,"Native fictional menu-bar summary with unread count, Today metrics, unavailable balance placeholders and quick actions.",region=(0,82,840,1118))
s.text("Local notifications need macOS permission. Quitting or sleeping pauses checks.",36,485,875,23,13)
slides.append(s)

s=Slide("My Prints","Your own prints. A useful history.")
s.image("my-prints-dark.png",36,160,600,295,"Native fictional My Prints history, with thumbnail cards, printer/plate context and finished or stopped statuses.",region=(490,650,2320,1200))
s.text("Find the job.",672,170,250,35,24,WHITE,True,"H2")
s.text("Search and filter your private cloud history by model, printer, plate, status or date.",672,222,250,112,18)
s.text("Keep the facts clear.",672,357,250,34,20,BLUE,True,"H2")
s.text("Recorded elapsed time stays separate from slice estimates.",672,405,250,69,17)
s.text("Read-only, account-scoped local history. Cloud coverage varies; this is not live printer telemetry or public model print totals.",36,480,880,37,13)
slides.append(s)

s=Slide("Trust & boundaries","Local data. Clear boundaries.")
for x,y,title,body in [(36,165,"History on your Mac","SQLite observations and preferences. The app does not encrypt the database."),(495,165,"Sessions in Keychain","User-initiated sign-in, creator validation and no saved password."),(36,319,"Read-only monitoring","No redemption, withdrawal, transfer or server-message-read actions."),(495,319,"Undocumented services","Availability and schemas can change. Missing data and reasons stay explicit.")]:
    s.rect(x,y,429,132);s.text(title,x+17,y+17,393,32,21,WHITE,True,"H2");s.text(body,x+17,y+61,393,60,16)
s.text("Independent, unofficial companion. Not affiliated with or endorsed by Bambu Lab or MakerWorld.",36,485,875,23,13)
slides.append(s)

s=Slide("Get started","Build your creator workspace.")
s.text("Native macOS. One focused view of what you observed.",36,146,880,35,21)
s.rect(36,213,565,184)
s.text("swift test\nbash scripts/build.sh\nopen dist/MakerGlance.app",55,239,523,125,23,WHITE)
s.image("icon.png",697,220,100,100,"Original MakerGlance app icon")
s.text("MakerGlance",643,339,263,35,27,WHITE,True,"H2")
s.text("Source preview · MIT",643,383,263,28,18,BLUE)
s.text("github.com/t0nyz0/MakerGlance",36,430,850,32,22,BLUE,True)
s.text("macOS 14+ target · Swift 6 · Xcode 16+\nPrivate preparation. No public binary or notarized release is being advertised.",36,477,880,35,12)
slides.append(s)

prs=Presentation();prs.slide_width=Pt(W);prs.slide_height=Pt(H)
# Remove python-pptx's unused template printer configuration from the package.
for relationship in list(prs.part.rels.values()):
    if relationship.reltype.endswith("/printerSettings"):
        prs.part.drop_rel(relationship.rId)
props=prs.core_properties
props.title="MakerGlance — See what moved. Keep the history."
props.subject="Native macOS creator analytics; all pictured data is fictional."
props.author="MakerGlance project";props.last_modified_by="MakerGlance project"
props.created=datetime(2026,10,22,tzinfo=timezone.utc);props.modified=props.created
props.keywords="MakerGlance, fictional demo, native macOS";props.revision=1

def rgb(code):return tuple(int(code[i:i+2],16)/255 for i in (0,2,4))
structure=[];transcript=[]
with tempfile.TemporaryDirectory(prefix="makerglance-deck-") as temporary:
    raw=Path(temporary)/"slides.pdf"
    pdf=canvas.Canvas(str(raw),pagesize=(W,H),pageCompression=1,invariant=True)
    pdf.setTitle(props.title);pdf.setAuthor("MakerGlance project");pdf.setCreator("MakerGlance documentation")
    for page_index,spec in enumerate(slides):
        slide=prs.slides.add_slide(prs.slide_layouts[6]);slide.background.fill.solid();slide.background.fill.fore_color.rgb=RGBColor.from_string(BG)
        pdf.addLiteral("/Artifact BMC");pdf.setFillColorRGB(*rgb(BG));pdf.rect(0,0,W,H,fill=1,stroke=0);pdf.addLiteral("EMC")
        elements=[];mcid=0;words=[]
        for item in spec.items:
            x,y,w,h=[item[k] for k in ("x","y","w","h")]
            if item["kind"]=="rect":
                shape=slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE,Pt(x),Pt(y),Pt(w),Pt(h));shape.fill.solid();shape.fill.fore_color.rgb=RGBColor.from_string(item["color"]);shape.line.fill.background();shape.adjustments[0]=0.08
                pdf.addLiteral("/Artifact BMC");pdf.setFillColorRGB(*rgb(item["color"]));pdf.roundRect(x,H-y-h,w,h,7,fill=1,stroke=0);pdf.addLiteral("EMC")
                continue
            role=item.get("tag","Figure");elements.append((mcid,role,item.get("alt")))
            pdf.addLiteral(f"/{role} <</MCID {mcid}>> BDC");mcid+=1
            if item["kind"]=="text":
                words.append(item["value"])
                box=slide.shapes.add_textbox(Pt(x),Pt(y),Pt(w),Pt(h));tf=box.text_frame;tf.word_wrap=False;tf.margin_left=tf.margin_right=tf.margin_top=tf.margin_bottom=0
                for index,line in enumerate(item["value"].splitlines()):
                    p=tf.paragraphs[0] if index==0 else tf.add_paragraph();p.space_after=Pt(0);p.space_before=Pt(0);p.line_spacing=1.18
                    run=p.add_run();run.text=line;run.font.name="Arial";run.font.size=Pt(item["size"]);run.font.bold=item["bold"];run.font.color.rgb=RGBColor.from_string(item["color"])
                    run._r.get_or_add_rPr().set("lang","en-US")
                font="DeckBold" if item["bold"] else "Deck";pdf.setFillColorRGB(*rgb(item["color"]))
                for index,line in enumerate(item["value"].splitlines()):
                    pdf.setFont(font,item["size"]);pdf.drawString(x,H-y-item["size"]-index*item["size"]*1.18,line)
            else:
                words.append("[Figure: "+item["alt"]+"]")
                pic=slide.shapes.add_picture(str(item["path"]),Pt(x),Pt(y),width=Pt(w),height=Pt(h))
                rx,ry,rw,rh=item["region"];pic.crop_left=rx/item["iw"];pic.crop_top=ry/item["ih"];pic.crop_right=(item["iw"]-rx-rw)/item["iw"];pic.crop_bottom=(item["ih"]-ry-rh)/item["ih"]
                pic._element.xpath(".//p:cNvPr")[0].set("descr",item["alt"])
                factor=w/rw;pdf.saveState();clip=pdf.beginPath();clip.rect(x,H-y-h,w,h);pdf.clipPath(clip,stroke=0,fill=0)
                pdf.drawImage(str(item["path"]),x-rx*factor,H-y-h-(item["ih"]-ry-rh)*factor,width=item["iw"]*factor,height=item["ih"]*factor,mask="auto");pdf.restoreState()
            pdf.addLiteral("EMC")
        pdf.addLiteral("/Artifact BMC");pdf.setStrokeColorRGB(*rgb("323540"));pdf.line(36,24,924,24)
        pdf.setFillColorRGB(*rgb(MUTED));pdf.setFont("Deck",9);pdf.drawString(36,10,"MakerGlance · Unofficial macOS companion · Fictional demo imagery");pdf.drawRightString(924,10,f"{page_index+1:02d} / {len(slides):02d}");pdf.addLiteral("EMC")
        slide.notes_slide.notes_text_frame.text="\n\n".join(words)+"\n\nAll demo identities and values are fictional. No account balances or private inbox are pictured."
        transcript.append("# Slide "+str(page_index+1)+"\n\n"+"\n\n".join(words));structure.append(elements);pdf.showPage()
    pdf.save();prs.save(ROOT/"MakerGlance.pptx")
    reader=PdfReader(raw);writer=PdfWriter();writer.clone_document_from_reader(reader)
    def N(v):return NameObject(v)
    root_tree=DictionaryObject({N("/Type"):N("/StructTreeRoot")});root_ref=writer._add_object(root_tree)
    document=DictionaryObject({N("/Type"):N("/StructElem"),N("/S"):N("/Document"),N("/P"):root_ref,N("/K"):ArrayObject()});doc_ref=writer._add_object(document)
    root_tree[N("/K")]=ArrayObject([doc_ref]);parent_numbers=ArrayObject()
    for index,(page,elements) in enumerate(zip(writer.pages,structure)):
        page[N("/StructParents")]=NumberObject(index)
        section=DictionaryObject({N("/Type"):N("/StructElem"),N("/S"):N("/Sect"),N("/P"):doc_ref,N("/Pg"):page.indirect_reference,N("/K"):ArrayObject()});section_ref=writer._add_object(section);document[N("/K")].append(section_ref)
        parents=ArrayObject()
        for mcid,role,alt in elements:
            element=DictionaryObject({N("/Type"):N("/StructElem"),N("/S"):N("/"+role),N("/P"):section_ref,N("/Pg"):page.indirect_reference,N("/K"):NumberObject(mcid)})
            if alt:element[N("/Alt")]=TextStringObject(alt)
            reference=writer._add_object(element);section[N("/K")].append(reference);parents.append(reference)
        parent_numbers.extend([NumberObject(index),parents])
    root_tree[N("/ParentTree")]=writer._add_object(DictionaryObject({N("/Nums"):parent_numbers}));root_tree[N("/ParentTreeNextKey")]=NumberObject(len(slides))
    writer._root_object[N("/StructTreeRoot")]=root_ref;writer._root_object[N("/MarkInfo")]=DictionaryObject({N("/Marked"):BooleanObject(True)})
    writer._root_object[N("/Lang")]=TextStringObject("en-US");writer._root_object[N("/ViewerPreferences")]=DictionaryObject({N("/DisplayDocTitle"):BooleanObject(True)})
    writer.add_metadata({"/Title":props.title,"/Author":"MakerGlance project","/Subject":props.subject,"/Creator":"MakerGlance documentation"})
    writer.write(ROOT/"MakerGlance.pdf")
(ROOT/"transcript.md").write_text("# MakerGlance presentation transcript\n\nAll pictured data and identities are fictional.\n\n"+"\n\n".join(transcript)+"\n")
print(f"Built {len(slides)} editable slides and tagged PDF pages from approved demo media.")
