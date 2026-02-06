<#
InlineNotepad.ps1
WinForms Notepad-like editor with:
- Encoding selection (ANSI, UTF-16 LE/BE, UTF-8, UTF-8 BOM)
- Encoding auto-detection on open
- EOL (CRLF/LF) detection and preservation
- Status bar (Ln/Col + EOL + Encoding)
- Fast Find/Replace on large files (RichTextBox.Find + ReplaceAllFast)
- Vista-style COM Save As dialog with Encoding + Line endings dropdowns

Run:
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\notepad.ps1
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\notepad.ps1 "C:\temp\file.txt"
#>

Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing       | Out-Null

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    [System.Windows.Forms.MessageBox]::Show(
        "This script must be run in STA.`n`nRun:`n  powershell.exe -STA -File `"$PSCommandPath`"",
        "InlineNotepad",
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

# Unique namespace per run to avoid Add-Type collisions
$ns = "InlineNotepad_" + ([guid]::NewGuid().ToString("N"))

$cs = @"
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace $ns
{
    public enum TextEncodingKind
    {
        Ansi = 0,
        Utf16LE = 1,
        Utf16BE = 2,
        Utf8 = 3,
        Utf8Bom = 4
    }

    public enum LineEndingKind
    {
        CRLF = 0,
        LF = 1
    }

    // -----------------------------
    // COM Save As dialog (Vista style) + custom controls
    // -----------------------------

    [Flags]
    internal enum FOS : uint
    {
        FOS_OVERWRITEPROMPT   = 0x00000002,
        FOS_STRICTFILETYPES   = 0x00000004,
        FOS_NOCHANGEDIR       = 0x00000008,
        FOS_PICKFOLDERS       = 0x00000020,
        FOS_FORCEFILESYSTEM   = 0x00000040,
        FOS_ALLNONSTORAGEITEMS= 0x00000080,
        FOS_NOVALIDATE        = 0x00000100,
        FOS_ALLOWMULTISELECT  = 0x00000200,
        FOS_PATHMUSTEXIST     = 0x00000800,
        FOS_FILEMUSTEXIST     = 0x00001000,
        FOS_CREATEPROMPT      = 0x00002000,
        FOS_SHAREAWARE        = 0x00004000,
        FOS_NOREADONLYRETURN  = 0x00008000,
        FOS_NOTESTFILECREATE  = 0x00010000,
        FOS_HIDEMRUPLACES     = 0x00020000,
        FOS_HIDEPINNEDPLACES  = 0x00040000,
        FOS_NODEREFERENCELINKS= 0x00100000,
        FOS_DONTADDTORECENT   = 0x02000000,
        FOS_FORCESHOWHIDDEN   = 0x10000000
    }

    internal enum SIGDN : uint
    {
        SIGDN_FILESYSPATH = 0x80058000
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct COMDLG_FILTERSPEC
    {
        [MarshalAs(UnmanagedType.LPWStr)]
        public string pszName;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string pszSpec;
    }

    [ComImport]
    [Guid("b4db1657-70d7-485e-8e3e-6fcb5a5c1802")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IModalWindow
    {
        [PreserveSig]
        int Show(IntPtr parent);
    }

    [ComImport]
    [Guid("42f85136-db7e-439c-85f1-e4075d135fc8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileDialog : IModalWindow
    {
        [PreserveSig]
        new int Show(IntPtr parent);

        void SetFileTypes(uint cFileTypes, [MarshalAs(UnmanagedType.LPArray)] COMDLG_FILTERSPEC[] rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(FOS fos);
        void GetOptions(out FOS pfos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, int fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
    }

    [ComImport]
    [Guid("84bccd23-5fde-4cdb-aea4-af64b83d78ab")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileSaveDialog : IFileDialog
    {
        [PreserveSig]
        new int Show(IntPtr parent);

        new void SetFileTypes(uint cFileTypes, [MarshalAs(UnmanagedType.LPArray)] COMDLG_FILTERSPEC[] rgFilterSpec);
        new void SetFileTypeIndex(uint iFileType);
        new void GetFileTypeIndex(out uint piFileType);
        new void Advise(IntPtr pfde, out uint pdwCookie);
        new void Unadvise(uint dwCookie);
        new void SetOptions(FOS fos);
        new void GetOptions(out FOS pfos);
        new void SetDefaultFolder(IShellItem psi);
        new void SetFolder(IShellItem psi);
        new void GetFolder(out IShellItem ppsi);
        new void GetCurrentSelection(out IShellItem ppsi);
        new void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        new void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        new void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        new void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        new void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        new void GetResult(out IShellItem ppsi);
        new void AddPlace(IShellItem psi, int fdap);
        new void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        new void Close(int hr);
        new void SetClientGuid(ref Guid guid);
        new void ClearClientData();
        new void SetFilter(IntPtr pFilter);

        void SetSaveAsItem(IShellItem psi);
        void SetProperties(IntPtr pStore);
        void SetCollectedProperties(IntPtr pList, int fAppendDefault);
        void GetProperties(out IntPtr ppStore);
        void ApplyProperties(IShellItem psi, IntPtr pStore, IntPtr hwnd, IntPtr pSink);
    }

    [ComImport]
    [Guid("E6FDD21A-163F-4975-9C8C-A69F1BA37034")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileDialogCustomize
    {
        void EnableOpenDropDown(int dwIDCtl);
        void AddMenu(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void AddPushButton(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void AddComboBox(int dwIDCtl);
        void AddRadioButtonList(int dwIDCtl);
        void AddCheckButton(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel, bool bChecked);
        void AddEditBox(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void AddSeparator(int dwIDCtl);
        void AddText(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetControlLabel(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetControlState(int dwIDCtl, out uint pdwState);
        void SetControlState(int dwIDCtl, uint dwState);
        void GetEditBoxText(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] out string ppszText);
        void SetEditBoxText(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void GetCheckButtonState(int dwIDCtl, out bool pbChecked);
        void SetCheckButtonState(int dwIDCtl, bool bChecked);
        void AddControlItem(int dwIDCtl, uint dwIDItem, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void RemoveControlItem(int dwIDCtl, uint dwIDItem);
        void RemoveAllControlItems(int dwIDCtl);
        void GetControlItemState(int dwIDCtl, uint dwIDItem, out uint pdwState);
        void SetControlItemState(int dwIDCtl, uint dwState);
        void GetSelectedControlItem(int dwIDCtl, out uint pdwIDItem);
        void SetSelectedControlItem(int dwIDCtl, uint dwIDItem);
        void StartVisualGroup(int dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void EndVisualGroup();
        void MakeProminent(int dwIDCtl);
        void SetControlItemText(int dwIDCtl, uint dwIDItem, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
    }

    [ComImport]
    [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(SIGDN sigdnName, out IntPtr ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport]
    [Guid("C0B4E2F3-BA21-4773-8DBA-335EC946EB8B")]
    internal class FileSaveDialogRCW
    {
    }

    internal enum EncodingChoice : uint
    {
        ANSI = 1,
        UTF16_LE = 2,
        UTF16_BE = 3,
        UTF8 = 4,
        UTF8_BOM = 5
    }

    internal enum LineEndingChoice : uint
    {
        Windows_CRLF = 10,
        Linux_LF = 11
    }

    internal sealed class SaveAsComResult
    {
        public string Path;
        public TextEncodingKind EncodingKind;
        public LineEndingKind LineEndingKind;

        public SaveAsComResult(string path, TextEncodingKind enc, LineEndingKind eol)
        {
            this.Path = path;
            this.EncodingKind = enc;
            this.LineEndingKind = eol;
        }
    }

    internal static class SaveAsCom
    {
        // No visual group; layout works best when we add:
        //   AddText, AddText   (labels row)
        //   AddComboBox, AddComboBox (combos row)
        private const int CID_LABEL_ENCODING = 3001;
        private const int CID_LABEL_EOL      = 3002;
        private const int CID_ENCODING       = 3003;
        private const int CID_EOL            = 3004;

        private static EncodingChoice MapEnc(TextEncodingKind k)
        {
            switch (k)
            {
                case TextEncodingKind.Ansi: return EncodingChoice.ANSI;
                case TextEncodingKind.Utf16LE: return EncodingChoice.UTF16_LE;
                case TextEncodingKind.Utf16BE: return EncodingChoice.UTF16_BE;
                case TextEncodingKind.Utf8: return EncodingChoice.UTF8;
                case TextEncodingKind.Utf8Bom: return EncodingChoice.UTF8_BOM;
            }
            return EncodingChoice.UTF8;
        }

        private static TextEncodingKind UnmapEnc(uint id, TextEncodingKind fallback)
        {
            if (id == 0) return fallback;
            EncodingChoice c = (EncodingChoice)id;
            switch (c)
            {
                case EncodingChoice.ANSI: return TextEncodingKind.Ansi;
                case EncodingChoice.UTF16_LE: return TextEncodingKind.Utf16LE;
                case EncodingChoice.UTF16_BE: return TextEncodingKind.Utf16BE;
                case EncodingChoice.UTF8: return TextEncodingKind.Utf8;
                case EncodingChoice.UTF8_BOM: return TextEncodingKind.Utf8Bom;
            }
            return fallback;
        }

        private static LineEndingChoice MapEol(LineEndingKind k)
        {
            if (k == LineEndingKind.LF) return LineEndingChoice.Linux_LF;
            return LineEndingChoice.Windows_CRLF;
        }

        private static LineEndingKind UnmapEol(uint id, LineEndingKind fallback)
        {
            if (id == 0) return fallback;
            LineEndingChoice c = (LineEndingChoice)id;
            if (c == LineEndingChoice.Linux_LF) return LineEndingKind.LF;
            if (c == LineEndingChoice.Windows_CRLF) return LineEndingKind.CRLF;
            return fallback;
        }

        public static SaveAsComResult Show(IntPtr parent, string currentPath, TextEncodingKind currentEnc, LineEndingKind currentEol)
        {
            IFileSaveDialog dlg = null;
            IFileDialogCustomize cust = null;
            IShellItem item = null;

            try
            {
                dlg = (IFileSaveDialog)new FileSaveDialogRCW();

                FOS fos;
                dlg.GetOptions(out fos);
                fos |= FOS.FOS_FORCEFILESYSTEM | FOS.FOS_PATHMUSTEXIST | FOS.FOS_OVERWRITEPROMPT;
                dlg.SetOptions(fos);

                dlg.SetTitle("Save As");

                string defaultName = "Untitled.txt";
                if (!string.IsNullOrEmpty(currentPath))
                    defaultName = Path.GetFileName(currentPath);
                dlg.SetFileName(defaultName);

                COMDLG_FILTERSPEC[] specs = new COMDLG_FILTERSPEC[2];
                specs[0].pszName = "Text Documents (*.txt)";
                specs[0].pszSpec = "*.txt";
                specs[1].pszName = "All Files (*.*)";
                specs[1].pszSpec = "*.*";
                dlg.SetFileTypes((uint)specs.Length, specs);
                dlg.SetFileTypeIndex(1);
                dlg.SetDefaultExtension("txt");

                cust = (IFileDialogCustomize)dlg;

                cust.AddText(CID_LABEL_ENCODING, "Encoding:");
                cust.AddComboBox(CID_ENCODING);
                
                cust.AddText(CID_LABEL_EOL, "Line endings:");
                cust.AddComboBox(CID_EOL);

                // Accessibility labels
                cust.SetControlLabel(CID_ENCODING, "Encoding");
                cust.SetControlLabel(CID_EOL, "Line endings");

                // Fill encoding
                cust.AddControlItem(CID_ENCODING, (uint)EncodingChoice.ANSI, "ANSI");
                cust.AddControlItem(CID_ENCODING, (uint)EncodingChoice.UTF16_LE, "UTF-16 LE");
                cust.AddControlItem(CID_ENCODING, (uint)EncodingChoice.UTF16_BE, "UTF-16 BE");
                cust.AddControlItem(CID_ENCODING, (uint)EncodingChoice.UTF8, "UTF-8");
                cust.AddControlItem(CID_ENCODING, (uint)EncodingChoice.UTF8_BOM, "UTF-8 with BOM");
                cust.SetSelectedControlItem(CID_ENCODING, (uint)MapEnc(currentEnc));

                // Fill EOL
                cust.AddControlItem(CID_EOL, (uint)LineEndingChoice.Windows_CRLF, "Windows (CRLF)");
                cust.AddControlItem(CID_EOL, (uint)LineEndingChoice.Linux_LF, "Linux (LF)");
                cust.SetSelectedControlItem(CID_EOL, (uint)MapEol(currentEol));

                int hr = dlg.Show(parent);

                // Cancel => HRESULT_FROM_WIN32(ERROR_CANCELLED) = 0x800704C7
                if (hr == unchecked((int)0x800704C7))
                    return null;

                if (hr < 0)
                    Marshal.ThrowExceptionForHR(hr);

                dlg.GetResult(out item);

                IntPtr psz;
                item.GetDisplayName(SIGDN.SIGDN_FILESYSPATH, out psz);
                string path = Marshal.PtrToStringUni(psz);
                Marshal.FreeCoTaskMem(psz);

                uint encId, eolId;
                cust.GetSelectedControlItem(CID_ENCODING, out encId);
                cust.GetSelectedControlItem(CID_EOL, out eolId);

                TextEncodingKind encKind = UnmapEnc(encId, currentEnc);
                LineEndingKind eolKind = UnmapEol(eolId, currentEol);

                return new SaveAsComResult(path, encKind, eolKind);
            }
            finally
            {
                if (item != null) Marshal.ReleaseComObject(item);
                if (cust != null) Marshal.ReleaseComObject(cust);
                if (dlg != null) Marshal.ReleaseComObject(dlg);
            }
        }
    }

    // -----------------------------
    // Core helpers
    // -----------------------------

    internal static class TextEncodingUtil
    {
        public static string ToDisplayName(TextEncodingKind k)
        {
            switch (k)
            {
                case TextEncodingKind.Ansi: return "ANSI";
                case TextEncodingKind.Utf16LE: return "UTF-16 LE";
                case TextEncodingKind.Utf16BE: return "UTF-16 BE";
                case TextEncodingKind.Utf8: return "UTF-8";
                case TextEncodingKind.Utf8Bom: return "UTF-8 with BOM";
            }
            return "UTF-8";
        }

        public static Encoding ToEncoding(TextEncodingKind k)
        {
            switch (k)
            {
                case TextEncodingKind.Ansi: return Encoding.Default;
                case TextEncodingKind.Utf16LE: return Encoding.Unicode;
                case TextEncodingKind.Utf16BE: return Encoding.BigEndianUnicode;
                case TextEncodingKind.Utf8: return new UTF8Encoding(false);
                case TextEncodingKind.Utf8Bom: return new UTF8Encoding(true);
            }
            return new UTF8Encoding(false);
        }
    }

    internal static class EolUtil
    {
        public static string ToDisplayName(LineEndingKind k)
        {
            if (k == LineEndingKind.LF) return "Unix (LF)";
            return "Windows (CRLF)";
        }

        public static LineEndingKind Detect(string text)
        {
            if (text == null) return LineEndingKind.CRLF;

            if (text.IndexOf("\r\n", StringComparison.Ordinal) >= 0)
                return LineEndingKind.CRLF;

            if (text.IndexOf("\n", StringComparison.Ordinal) >= 0)
                return LineEndingKind.LF;

            return LineEndingKind.CRLF;
        }

        public static string NormalizeToLF(string text)
        {
            if (text == null) return "";
            string t = text.Replace("\r\n", "\n");
            t = t.Replace("\r", "\n");
            return t;
        }

        public static string NormalizeToCRLF(string text)
        {
            string lf = NormalizeToLF(text);
            return lf.Replace("\n", "\r\n");
        }

        public static string ApplyStyle(string editorText, LineEndingKind style)
        {
            string lf = NormalizeToLF(editorText);
            if (style == LineEndingKind.LF)
                return lf;
            return lf.Replace("\n", "\r\n");
        }
    }

    public sealed class NotepadApp
    {
        [STAThread]
        public static int Run(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string fileToOpen = null;
            if (args != null)
            {
                for (int i = 0; i < args.Length; i++)
                {
                    string a = args[i] ?? "";
                    if (!a.StartsWith("/") && fileToOpen == null)
                        fileToOpen = a;
                }
            }

            NotepadForm f = new NotepadForm();
            if (!string.IsNullOrEmpty(fileToOpen))
                f.OpenFileFromPath(fileToOpen);

            Application.Run(f);
            return 0;
        }
    }

    public sealed class NotepadForm : Form
    {
        private const int WM_SETREDRAW = 0x000B;

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        private RichTextBox _edit;
        private StatusStrip _status;
        private ToolStripStatusLabel _pos;
        private ToolStripStatusLabel _eol;
        private ToolStripStatusLabel _enc;

        private string _currentPath;
        private bool _dirty;

        private TextEncodingKind _encodingKind;
        private LineEndingKind _lineEndingKind;

        private bool _suppressTextChanged;

        // Find/Replace state
        private string _findText;
        private string _replaceText;
        private bool _matchCase;
        private bool _reverse; // find direction only (up/down)

        private FindForm _findForm;
        private ReplaceForm _replaceForm;

        public NotepadForm()
        {
            _currentPath = null;
            _dirty = false;

            _encodingKind = TextEncodingKind.Utf8;
            _lineEndingKind = LineEndingKind.CRLF;

            _suppressTextChanged = false;

            _findText = "";
            _replaceText = "";
            _matchCase = false;
            _reverse = false;

            _findForm = null;
            _replaceForm = null;

            this.Text = "Untitled - Notepad";
            this.Width = 950;
            this.Height = 720;

            BuildUi();
            UpdateTitle();
            UpdateStatusAll();

            this.Shown += new EventHandler(delegate(object s, EventArgs e) { FocusEditorSoon(); });
            this.Activated += new EventHandler(delegate(object s, EventArgs e) { FocusEditorSoon(); });
        }

        private void BuildUi()
        {
            _edit = new RichTextBox();
            _edit.Dock = DockStyle.Fill;
            _edit.Multiline = true;
            _edit.AcceptsTab = true;
            _edit.WordWrap = false;
            _edit.ScrollBars = RichTextBoxScrollBars.Both;
            _edit.HideSelection = false;
            _edit.ReadOnly = false;
            _edit.Enabled = true;
            _edit.DetectUrls = false;
            _edit.MaxLength = 0;
            _edit.ShortcutsEnabled = true;
            _edit.Font = new Font(FontFamily.GenericMonospace, 11f);

            _edit.TextChanged += new EventHandler(delegate(object s, EventArgs e)
            {
                if (_suppressTextChanged) return;
                if (!_dirty)
                {
                    _dirty = true;
                    UpdateTitle();
                }
                UpdateCaretPos();
            });

            _edit.SelectionChanged += new EventHandler(delegate(object s, EventArgs e) { UpdateCaretPos(); });
            _edit.KeyUp += new KeyEventHandler(delegate(object s, KeyEventArgs e) { UpdateCaretPos(); });
            _edit.MouseUp += new MouseEventHandler(delegate(object s, MouseEventArgs e) { UpdateCaretPos(); });

            _edit.AllowDrop = true;
            _edit.DragEnter += new DragEventHandler(delegate(object s, DragEventArgs e)
            {
                if (e.Data != null && e.Data.GetDataPresent(DataFormats.FileDrop))
                    e.Effect = DragDropEffects.Copy;
            });
            _edit.DragDrop += new DragEventHandler(delegate(object s, DragEventArgs e)
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files != null && files.Length > 0)
                    OpenFileFromPath(files[0]);
            });

            this.Controls.Add(_edit);

            _status = new StatusStrip();
            _pos = new ToolStripStatusLabel("Ln 1, Col 1");
            _eol = new ToolStripStatusLabel("Windows (CRLF)");
            _enc = new ToolStripStatusLabel("UTF-8");

            _pos.BorderSides = ToolStripStatusLabelBorderSides.Right;
            _eol.BorderSides = ToolStripStatusLabelBorderSides.Right;

            _status.Items.Add(_pos);
            _status.Items.Add(_eol);
            _status.Items.Add(_enc);
            _status.Dock = DockStyle.Bottom;

            this.Controls.Add(_status);

            MenuStrip menu = new MenuStrip();
            menu.MenuDeactivate += new EventHandler(delegate(object s, EventArgs e) { FocusEditorSoon(); });

            // FILE
            ToolStripMenuItem mFile = new ToolStripMenuItem("&File");

            ToolStripMenuItem miNew = new ToolStripMenuItem("&New");
            miNew.ShortcutKeys = Keys.Control | Keys.N;
            miNew.Click += new EventHandler(delegate(object s, EventArgs e) { NewFile(); });

            ToolStripMenuItem miOpen = new ToolStripMenuItem("&Open...");
            miOpen.ShortcutKeys = Keys.Control | Keys.O;
            miOpen.Click += new EventHandler(delegate(object s, EventArgs e) { OpenFileDialogUI(); });

            ToolStripMenuItem miSave = new ToolStripMenuItem("&Save");
            miSave.ShortcutKeys = Keys.Control | Keys.S;
            miSave.Click += new EventHandler(delegate(object s, EventArgs e) { Save(); });

            ToolStripMenuItem miSaveAs = new ToolStripMenuItem("Save &As...");
            miSaveAs.Click += new EventHandler(delegate(object s, EventArgs e) { SaveAs(); });

            ToolStripMenuItem miExit = new ToolStripMenuItem("E&xit");
            miExit.Click += new EventHandler(delegate(object s, EventArgs e) { this.Close(); });

            mFile.DropDownItems.Add(miNew);
            mFile.DropDownItems.Add(miOpen);
            mFile.DropDownItems.Add(new ToolStripSeparator());
            mFile.DropDownItems.Add(miSave);
            mFile.DropDownItems.Add(miSaveAs);
            mFile.DropDownItems.Add(new ToolStripSeparator());
            mFile.DropDownItems.Add(miExit);

            // EDIT
            ToolStripMenuItem mEdit = new ToolStripMenuItem("&Edit");

            ToolStripMenuItem miUndo = new ToolStripMenuItem("&Undo");
            miUndo.ShortcutKeys = Keys.Control | Keys.Z;
            miUndo.Click += new EventHandler(delegate(object s, EventArgs e) { if (_edit.CanUndo) _edit.Undo(); FocusEditorSoon(); });

            ToolStripMenuItem miCut = new ToolStripMenuItem("Cu&t");
            miCut.ShortcutKeys = Keys.Control | Keys.X;
            miCut.Click += new EventHandler(delegate(object s, EventArgs e) { _edit.Cut(); FocusEditorSoon(); });

            ToolStripMenuItem miCopy = new ToolStripMenuItem("&Copy");
            miCopy.ShortcutKeys = Keys.Control | Keys.C;
            miCopy.Click += new EventHandler(delegate(object s, EventArgs e) { _edit.Copy(); FocusEditorSoon(); });

            ToolStripMenuItem miPaste = new ToolStripMenuItem("&Paste");
            miPaste.ShortcutKeys = Keys.Control | Keys.V;
            miPaste.Click += new EventHandler(delegate(object s, EventArgs e) { _edit.Paste(); FocusEditorSoon(); });

            ToolStripMenuItem miDelete = new ToolStripMenuItem("De&lete");
            miDelete.ShortcutKeys = Keys.Delete;
            miDelete.Click += new EventHandler(delegate(object s, EventArgs e) { if (_edit.SelectionLength > 0) _edit.SelectedText = ""; FocusEditorSoon(); });

            ToolStripMenuItem miSelectAll = new ToolStripMenuItem("Select &All");
            miSelectAll.ShortcutKeys = Keys.Control | Keys.A;
            miSelectAll.Click += new EventHandler(delegate(object s, EventArgs e) { _edit.SelectAll(); FocusEditorSoon(); });

            ToolStripMenuItem miTimeDate = new ToolStripMenuItem("Time/&Date");
            miTimeDate.ShortcutKeys = Keys.F5;
            miTimeDate.Click += new EventHandler(delegate(object s, EventArgs e) { InsertTimeDate(); });

            mEdit.DropDownOpening += new EventHandler(delegate(object s, EventArgs e)
            {
                miUndo.Enabled = _edit.CanUndo;
                bool hasSel = (_edit.SelectionLength > 0);
                miCut.Enabled = hasSel;
                miCopy.Enabled = hasSel;
                miDelete.Enabled = hasSel;
                miPaste.Enabled = Clipboard.ContainsText();
            });

            mEdit.DropDownItems.Add(miUndo);
            mEdit.DropDownItems.Add(new ToolStripSeparator());
            mEdit.DropDownItems.Add(miCut);
            mEdit.DropDownItems.Add(miCopy);
            mEdit.DropDownItems.Add(miPaste);
            mEdit.DropDownItems.Add(miDelete);
            mEdit.DropDownItems.Add(new ToolStripSeparator());
            mEdit.DropDownItems.Add(miSelectAll);
            mEdit.DropDownItems.Add(miTimeDate);

            // SEARCH
            ToolStripMenuItem mSearch = new ToolStripMenuItem("&Search");

            ToolStripMenuItem miFind = new ToolStripMenuItem("&Find...");
            miFind.ShortcutKeys = Keys.Control | Keys.F;
            miFind.Click += new EventHandler(delegate(object s, EventArgs e) { ShowFindDialog(); });

            ToolStripMenuItem miFindNext = new ToolStripMenuItem("Find &Next");
            miFindNext.ShortcutKeys = Keys.F3;
            miFindNext.Click += new EventHandler(delegate(object s, EventArgs e)
            {
                if (string.IsNullOrEmpty(_findText)) { ShowFindDialog(); return; }
                SearchCurrent(false);
            });

            ToolStripMenuItem miReplace = new ToolStripMenuItem("&Replace...");
            miReplace.ShortcutKeys = Keys.Control | Keys.H;
            miReplace.Click += new EventHandler(delegate(object s, EventArgs e) { ShowReplaceDialog(); });

            ToolStripMenuItem miGoTo = new ToolStripMenuItem("&Go To...");
            miGoTo.ShortcutKeys = Keys.Control | Keys.G;
            miGoTo.Click += new EventHandler(delegate(object s, EventArgs e) { GoToLineUI(); });

            mSearch.DropDownOpening += new EventHandler(delegate(object s, EventArgs e)
            {
                miFindNext.Enabled = !string.IsNullOrEmpty(_findText);
            });

            mSearch.DropDownItems.Add(miFind);
            mSearch.DropDownItems.Add(miFindNext);
            mSearch.DropDownItems.Add(miReplace);
            mSearch.DropDownItems.Add(new ToolStripSeparator());
            mSearch.DropDownItems.Add(miGoTo);

            // HELP
            ToolStripMenuItem mHelp = new ToolStripMenuItem("&Help");
            ToolStripMenuItem miAbout = new ToolStripMenuItem("&About...");
            miAbout.Click += new EventHandler(delegate(object s, EventArgs e)
            {
                MessageBox.Show(this, "InlineNotepad (PowerShell + inline C#)\nEncoding + EOL preserved.\nFast Find/Replace for large files.", "About",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
            });
            mHelp.DropDownItems.Add(miAbout);

            menu.Items.Add(mFile);
            menu.Items.Add(mEdit);
            menu.Items.Add(mSearch);
            menu.Items.Add(mHelp);

            this.MainMenuStrip = menu;
            menu.Dock = DockStyle.Top;
            this.Controls.Add(menu);

            this.FormClosing += new FormClosingEventHandler(delegate(object s, FormClosingEventArgs e)
            {
                if (!ConfirmDiscardIfDirty()) e.Cancel = true;
            });
        }

        private void FocusEditorSoon()
        {
            if (_edit == null) return;
            try
            {
                this.BeginInvoke((MethodInvoker)delegate
                {
                    _edit.Enabled = true;
                    _edit.ReadOnly = false;
                    this.ActiveControl = _edit;
                    _edit.Focus();
                });
            }
            catch { }
        }

        private void UpdateTitle()
        {
            string name = string.IsNullOrEmpty(_currentPath) ? "Untitled" : Path.GetFileName(_currentPath);
            this.Text = name + " - Notepad";
        }

        private void UpdateCaretPos()
        {
            int idx = _edit.SelectionStart;
            int line = _edit.GetLineFromCharIndex(idx);
            int col = idx - _edit.GetFirstCharIndexFromLine(line);
            if (line < 0) line = 0;
            if (col < 0) col = 0;
            _pos.Text = string.Format("Ln {0}, Col {1}", line + 1, col + 1);
        }

        private void UpdateStatusAll()
        {
            _eol.Text = EolUtil.ToDisplayName(_lineEndingKind);
            _enc.Text = TextEncodingUtil.ToDisplayName(_encodingKind);
            UpdateCaretPos();
        }

        private void InsertTimeDate()
        {
            string stamp = DateTime.Now.ToShortTimeString() + " " + DateTime.Now.ToShortDateString();
            _edit.SelectedText = stamp;
            FocusEditorSoon();
        }

        private void NewFile()
        {
            if (!ConfirmDiscardIfDirty()) return;

            _suppressTextChanged = true;
            BeginBulkUpdate();
            try
            {
                _edit.Clear();
                _edit.SelectionStart = 0;
                _edit.SelectionLength = 0;
            }
            finally
            {
                EndBulkUpdate();
                _suppressTextChanged = false;
            }

            _currentPath = null;
            _dirty = false;

            _encodingKind = TextEncodingKind.Utf8;
            _lineEndingKind = LineEndingKind.CRLF;

            UpdateTitle();
            UpdateStatusAll();
            FocusEditorSoon();
        }

        private void OpenFileDialogUI()
        {
            if (!ConfirmDiscardIfDirty()) return;

            using (OpenFileDialog ofd = new OpenFileDialog())
            {
                ofd.Filter = "Text Documents (*.txt)|*.txt|All Files (*.*)|*.*";
                ofd.Title = "Open";
                if (ofd.ShowDialog(this) == DialogResult.OK)
                    OpenFileFromPath(ofd.FileName);
            }
        }

        public void OpenFileFromPath(string path)
        {
            try
            {
                if (!File.Exists(path))
                {
                    MessageBox.Show(this, "File not found.", "Notepad",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                this.Cursor = Cursors.WaitCursor;

                TextEncodingKind encKind;
                Encoding enc;
                string rawText = ReadAllTextAuto(path, out encKind, out enc);

                LineEndingKind eolKind = EolUtil.Detect(rawText);

                // Normalize for editor control (CRLF internally)
                string editorText = EolUtil.NormalizeToCRLF(rawText);

                _suppressTextChanged = true;
                BeginBulkUpdate();
                try
                {
                    _edit.Text = editorText;
                    _edit.SelectionStart = 0;
                    _edit.SelectionLength = 0;
                }
                finally
                {
                    EndBulkUpdate();
                    _suppressTextChanged = false;
                }

                _currentPath = path;
                _dirty = false;

                _encodingKind = encKind;
                _lineEndingKind = eolKind;

                UpdateTitle();
                UpdateStatusAll();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Could not open file:\n" + ex.Message, "Notepad",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                this.Cursor = Cursors.Default;
                FocusEditorSoon();
            }
        }

        private void Save()
        {
            if (string.IsNullOrEmpty(_currentPath))
            {
                SaveAs();
                return;
            }

            try
            {
                string toWrite = EolUtil.ApplyStyle(_edit.Text ?? "", _lineEndingKind);
                Encoding enc = TextEncodingUtil.ToEncoding(_encodingKind);

                using (FileStream fs = new FileStream(_currentPath, FileMode.Create, FileAccess.Write, FileShare.Read))
                using (StreamWriter sw = new StreamWriter(fs, enc))
                {
                    sw.Write(toWrite);
                }

                _dirty = false;
                UpdateTitle();
                UpdateStatusAll();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Could not save file:\n" + ex.Message, "Notepad",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }

            FocusEditorSoon();
        }

        private void SaveAs()
        {
            try
            {
                SaveAsComResult r = SaveAsCom.Show(this.Handle, _currentPath, _encodingKind, _lineEndingKind);
                if (r == null) { FocusEditorSoon(); return; }   // cancelled

                if (string.IsNullOrEmpty(r.Path)) { FocusEditorSoon(); return; }

                _currentPath = r.Path;
                _encodingKind = r.EncodingKind;
                _lineEndingKind = r.LineEndingKind;

                Save();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Save As failed:\n" + ex.Message, "Notepad",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }

            FocusEditorSoon();
        }

        private bool ConfirmDiscardIfDirty()
        {
            if (!_dirty) return true;

            string name = string.IsNullOrEmpty(_currentPath) ? "Untitled" : Path.GetFileName(_currentPath);

            DialogResult r = MessageBox.Show(this,
                "Do you want to save changes to " + name + "?",
                "Notepad",
                MessageBoxButtons.YesNoCancel,
                MessageBoxIcon.Question);

            if (r == DialogResult.Cancel) return false;
            if (r == DialogResult.Yes) Save();
            return true;
        }

        private void BeginBulkUpdate()
        {
            try
            {
                if (_edit != null && _edit.IsHandleCreated)
                    SendMessage(_edit.Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
            }
            catch { }
        }

        private void EndBulkUpdate()
        {
            try
            {
                if (_edit != null && _edit.IsHandleCreated)
                {
                    SendMessage(_edit.Handle, WM_SETREDRAW, new IntPtr(1), IntPtr.Zero);
                    _edit.Invalidate();
                    _edit.Refresh();
                }
            }
            catch { }
        }

        // -----------------------------
        // FAST Find/Replace
        // -----------------------------
        private RichTextBoxFinds BuildFindFlags(bool reverse)
        {
            RichTextBoxFinds flags = RichTextBoxFinds.None;
            if (_matchCase) flags |= RichTextBoxFinds.MatchCase;
            if (reverse) flags |= RichTextBoxFinds.Reverse;
            return flags;
        }

        private bool SearchCurrent(bool suppressNotFoundAlert)
        {
            if (string.IsNullOrEmpty(_findText))
                return false;

            int idx = -1;

            if (_reverse)
            {
                // Notepad-like "Up": search backwards from just before the caret/selection
                int end = _edit.SelectionStart;

                // If there's a selection, search before it; if caret only, search before caret
                if (end > 0) end -= 1;

                if (end <= 0)
                {
                    idx = -1;
                }
                else
                {
                    RichTextBoxFinds flags = RichTextBoxFinds.Reverse;
                    if (_matchCase) flags |= RichTextBoxFinds.MatchCase;

                    // IMPORTANT: end must be >= start; use range [0..end] and Reverse
                    idx = _edit.Find(_findText, 0, end, flags);
                }
            }
            else
            {
                // Notepad-like "Down": search forward from end of current selection
                int start = _edit.SelectionStart + _edit.SelectionLength;
                int end = _edit.TextLength;

                if (start < 0) start = 0;
                if (start > end) start = end;

                RichTextBoxFinds flags = RichTextBoxFinds.None;
                if (_matchCase) flags |= RichTextBoxFinds.MatchCase;

                idx = _edit.Find(_findText, start, end, flags);
            }

            if (idx >= 0)
            {
                _edit.Select(idx, _findText.Length);
                _edit.ScrollToCaret();
                FocusEditorSoon();
                return true;
            }

            if (!suppressNotFoundAlert)
            {
                IWin32Window owner = (IWin32Window)_findForm;
                if (owner == null) owner = (IWin32Window)_replaceForm;
                if (owner == null) owner = (IWin32Window)this;

                MessageBox.Show(owner,
                    "Cannot find \"" + _findText + "\"",
                    "Notepad",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }

            FocusEditorSoon();
            return false;
        }


        private void ReplaceSel(bool view)
        {
            if (string.IsNullOrEmpty(_findText))
                return;

            int len = _edit.SelectionLength;
            if (len != _findText.Length)
                return;

            string sel = _edit.SelectedText ?? "";
            StringComparison cmp = _matchCase ? StringComparison.CurrentCulture : StringComparison.CurrentCultureIgnoreCase;
            if (string.Compare(sel, _findText, cmp) != 0)
                return;

            int start = _edit.SelectionStart;
            string repl = _replaceText ?? "";
            _edit.SelectedText = repl;

            _edit.SelectionStart = start;
            _edit.SelectionLength = repl.Length;

            if (view)
                _edit.ScrollToCaret();

            _dirty = true;
            UpdateTitle();
        }

        private int ReplaceAllFast()
        {
            if (string.IsNullOrEmpty(_findText))
                return 0;

            string hay = _edit.Text ?? "";
            if (hay.Length == 0)
                return 0;

            string find = _findText;
            string repl = _replaceText ?? "";
            StringComparison cmp = _matchCase ? StringComparison.CurrentCulture : StringComparison.CurrentCultureIgnoreCase;

            int count = 0;
            int pos = 0;

            StringBuilder sb = new StringBuilder(hay.Length);

            while (true)
            {
                int idx = hay.IndexOf(find, pos, cmp);
                if (idx < 0)
                {
                    sb.Append(hay, pos, hay.Length - pos);
                    break;
                }

                sb.Append(hay, pos, idx - pos);
                sb.Append(repl);
                pos = idx + find.Length;
                count++;
            }

            if (count == 0)
                return 0;

            _suppressTextChanged = true;
            BeginBulkUpdate();
            try
            {
                _edit.Text = sb.ToString();
                _edit.SelectionStart = 0;
                _edit.SelectionLength = 0;
            }
            finally
            {
                EndBulkUpdate();
                _suppressTextChanged = false;
            }

            _dirty = true;
            UpdateTitle();
            UpdateStatusAll();
            FocusEditorSoon();
            return count;
        }

        // -----------------------------
        // Find / Replace dialogs (modeless)
        // -----------------------------
        private void ShowFindDialog()
        {
            if (_findForm != null) { _findForm.Focus(); return; }

            _findForm = new FindForm(_findText, _matchCase, !_reverse);

            _findForm.FindNextClicked += new EventHandler(delegate(object s, EventArgs e)
            {
                _findText = _findForm.FindText ?? "";
                _matchCase = _findForm.MatchCase;
                _reverse = !_findForm.SearchDown;

                if (!string.IsNullOrEmpty(_findText))
                    SearchCurrent(false);
            });

            _findForm.FormClosed += new FormClosedEventHandler(delegate(object s, FormClosedEventArgs e)
            {
                _findForm = null;
                FocusEditorSoon();
            });

            _findForm.Show(this);
        }

        private void ShowReplaceDialog()
        {
            if (_replaceForm != null) { _replaceForm.Focus(); return; }

            _reverse = false; // replace searches down

            _replaceForm = new ReplaceForm(_findText, _replaceText, _matchCase);

            _replaceForm.FindNextClicked += new EventHandler(delegate(object s, EventArgs e)
            {
                _findText = _replaceForm.FindText ?? "";
                _replaceText = _replaceForm.ReplaceText ?? "";
                _matchCase = _replaceForm.MatchCase;
                _reverse = false;

                if (!string.IsNullOrEmpty(_findText))
                    SearchCurrent(false);
            });

            _replaceForm.ReplaceClicked += new EventHandler(delegate(object s, EventArgs e)
            {
                _findText = _replaceForm.FindText ?? "";
                _replaceText = _replaceForm.ReplaceText ?? "";
                _matchCase = _replaceForm.MatchCase;
                _reverse = false;

                if (!string.IsNullOrEmpty(_findText))
                {
                    ReplaceSel(true);
                    SearchCurrent(false);
                }
            });

            _replaceForm.ReplaceAllClicked += new EventHandler(delegate(object s, EventArgs e)
            {
                _findText = _replaceForm.FindText ?? "";
                _replaceText = _replaceForm.ReplaceText ?? "";
                _matchCase = _replaceForm.MatchCase;
                _reverse = false;

                if (!string.IsNullOrEmpty(_findText))
                {
                    int count = ReplaceAllFast();
                    MessageBox.Show(_replaceForm,
                        string.Format("Replaced {0} occurrence(s).", count),
                        "Notepad",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Information);
                }
            });

            _replaceForm.FormClosed += new FormClosedEventHandler(delegate(object s, FormClosedEventArgs e)
            {
                _replaceForm = null;
                FocusEditorSoon();
            });

            _replaceForm.Show(this);
        }

        // -----------------------------
        // Go To
        // -----------------------------
        private void GoToLineUI()
        {
            int maxLine = _edit.Lines != null ? _edit.Lines.Length : 1;
            if (maxLine < 1) maxLine = 1;

            using (GoToForm dlg = new GoToForm(maxLine))
            {
                if (dlg.ShowDialog(this) == DialogResult.OK)
                {
                    int line = dlg.LineNumber;
                    if (line < 1) line = 1;
                    if (line > maxLine) line = maxLine;

                    int idx = _edit.GetFirstCharIndexFromLine(line - 1);
                    if (idx >= 0)
                    {
                        _edit.SelectionStart = idx;
                        _edit.SelectionLength = 0;
                        _edit.ScrollToCaret();
                    }
                }
            }
            FocusEditorSoon();
        }

        // -----------------------------
        // Open detection
        // -----------------------------
        private static string ReadAllTextAuto(string path, out TextEncodingKind kind, out Encoding encoding)
        {
            kind = TextEncodingKind.Utf8;
            encoding = TextEncodingUtil.ToEncoding(kind);

            byte[] first4 = new byte[4];
            int n = 0;

            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                n = fs.Read(first4, 0, first4.Length);
            }

            // BOM checks
            if (n >= 2)
            {
                if (first4[0] == 0xFF && first4[1] == 0xFE)
                {
                    kind = TextEncodingKind.Utf16LE;
                    encoding = TextEncodingUtil.ToEncoding(kind);
                    return ReadWithEncoding(path, encoding);
                }
                if (first4[0] == 0xFE && first4[1] == 0xFF)
                {
                    kind = TextEncodingKind.Utf16BE;
                    encoding = TextEncodingUtil.ToEncoding(kind);
                    return ReadWithEncoding(path, encoding);
                }
            }
            if (n >= 3)
            {
                if (first4[0] == 0xEF && first4[1] == 0xBB && first4[2] == 0xBF)
                {
                    kind = TextEncodingKind.Utf8Bom;
                    encoding = TextEncodingUtil.ToEncoding(kind);
                    return ReadWithEncoding(path, encoding);
                }
            }

            // UTF-16 heuristic (no BOM)
            if (LooksLikeUtf16(path, true))
            {
                kind = TextEncodingKind.Utf16LE;
                encoding = TextEncodingUtil.ToEncoding(kind);
                return ReadWithEncoding(path, encoding);
            }
            if (LooksLikeUtf16(path, false))
            {
                kind = TextEncodingKind.Utf16BE;
                encoding = TextEncodingUtil.ToEncoding(kind);
                return ReadWithEncoding(path, encoding);
            }

            // UTF-8 strict sample, else ANSI
            if (IsValidUtf8Sample(path))
            {
                kind = TextEncodingKind.Utf8;
                encoding = TextEncodingUtil.ToEncoding(kind);
                return ReadWithEncoding(path, encoding);
            }

            kind = TextEncodingKind.Ansi;
            encoding = TextEncodingUtil.ToEncoding(kind);
            return ReadWithEncoding(path, encoding);
        }

        private static string ReadWithEncoding(string path, Encoding enc)
        {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (StreamReader sr = new StreamReader(fs, enc, false, 64 * 1024))
            {
                return sr.ReadToEnd();
            }
        }

        private static bool LooksLikeUtf16(string path, bool littleEndian)
        {
            byte[] buf = new byte[4096];
            int n = 0;
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                n = fs.Read(buf, 0, buf.Length);
            }
            if (n < 64) return false;

            int zeros = 0;
            int checkedPairs = 0;

            for (int i = 0; i + 1 < n; i += 2)
            {
                byte b0 = buf[i];
                byte b1 = buf[i + 1];

                if (littleEndian)
                {
                    if (b1 == 0x00) zeros++;
                }
                else
                {
                    if (b0 == 0x00) zeros++;
                }
                checkedPairs++;
            }

            return (checkedPairs > 0 && (zeros * 100 / checkedPairs) >= 40);
        }

        private static bool IsValidUtf8Sample(string path)
        {
            byte[] buf = new byte[65536];
            int n = 0;
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                n = fs.Read(buf, 0, buf.Length);
            }
            if (n <= 0) return true;

            UTF8Encoding utf8Strict = new UTF8Encoding(false, true);
            try
            {
                utf8Strict.GetString(buf, 0, n);
                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    internal sealed class FindForm : Form
    {
        private TextBox _t;
        private CheckBox _matchCase;
        private RadioButton _up;
        private RadioButton _down;
        private Button _findNext;

        public event EventHandler FindNextClicked;

        public string FindText { get { return _t.Text; } }
        public bool MatchCase { get { return _matchCase.Checked; } }
        public bool SearchDown { get { return _down.Checked; } }

        public FindForm(string initialFind, bool matchCase, bool searchDown)
        {
            this.Text = "Find";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.CenterParent;
            this.AutoScaleMode = AutoScaleMode.Font;
            this.ClientSize = new Size(420, 165);

            Label l = new Label();
            l.Left = 10; l.Top = 15; l.Width = 70; l.Text = "Find what:";

            _t = new TextBox();
            _t.Left = 85; _t.Top = 12; _t.Width = 320;
            _t.Text = (initialFind == null) ? "" : initialFind;

            _matchCase = new CheckBox();
            _matchCase.Left = 85; _matchCase.Top = 42; _matchCase.Width = 120;
            _matchCase.Text = "Match case";
            _matchCase.Checked = matchCase;

            GroupBox g = new GroupBox();
            g.Left = 85; g.Top = 68; g.Width = 210; g.Height = 55;
            g.Text = "Direction";

            _up = new RadioButton();
            _up.Left = 10; _up.Top = 22; _up.Width = 60; _up.Text = "Up";

            _down = new RadioButton();
            _down.Left = 110; _down.Top = 22; _down.Width = 80; _down.Text = "Down";

            _down.Checked = searchDown;
            _up.Checked = !searchDown;

            g.Controls.Add(_up);
            g.Controls.Add(_down);

            _findNext = new Button();
            _findNext.Left = 315; _findNext.Top = 68; _findNext.Width = 90; _findNext.Text = "Find Next";
            _findNext.Click += new EventHandler(delegate(object s, EventArgs e)
            {
                if (FindNextClicked != null) FindNextClicked(this, EventArgs.Empty);
            });

            Button cancel = new Button();
            cancel.Left = 315; cancel.Top = 98; cancel.Width = 90; cancel.Text = "Cancel";
            cancel.Click += new EventHandler(delegate(object s, EventArgs e) { this.Close(); });

            _t.TextChanged += new EventHandler(delegate(object s, EventArgs e)
            {
                _findNext.Enabled = (_t.Text != null && _t.Text.Length > 0);
            });
            _findNext.Enabled = (_t.Text != null && _t.Text.Length > 0);

            this.Controls.Add(l);
            this.Controls.Add(_t);
            this.Controls.Add(_matchCase);
            this.Controls.Add(g);
            this.Controls.Add(_findNext);
            this.Controls.Add(cancel);

            this.AcceptButton = _findNext;
            this.CancelButton = cancel;
        }
    }

    internal sealed class ReplaceForm : Form
    {
        private TextBox _find;
        private TextBox _repl;
        private CheckBox _matchCase;

        private Button _findNext;
        private Button _replace;
        private Button _replaceAll;

        public event EventHandler FindNextClicked;
        public event EventHandler ReplaceClicked;
        public event EventHandler ReplaceAllClicked;

        public string FindText { get { return _find.Text; } }
        public string ReplaceText { get { return _repl.Text; } }
        public bool MatchCase { get { return _matchCase.Checked; } }

        public ReplaceForm(string initialFind, string initialReplace, bool matchCase)
        {
            this.Text = "Replace";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.CenterParent;
            this.AutoScaleMode = AutoScaleMode.Font;
            this.ClientSize = new Size(470, 190);

            Label lf = new Label();
            lf.Left = 10; lf.Top = 15; lf.Width = 90; lf.Text = "Find what:";

            _find = new TextBox();
            _find.Left = 110; _find.Top = 12; _find.Width = 260;
            _find.Text = (initialFind == null) ? "" : initialFind;

            Label lr = new Label();
            lr.Left = 10; lr.Top = 45; lr.Width = 90; lr.Text = "Replace with:";

            _repl = new TextBox();
            _repl.Left = 110; _repl.Top = 42; _repl.Width = 260;
            _repl.Text = (initialReplace == null) ? "" : initialReplace;

            _matchCase = new CheckBox();
            _matchCase.Left = 110; _matchCase.Top = 72; _matchCase.Width = 120;
            _matchCase.Text = "Match case";
            _matchCase.Checked = matchCase;

            _findNext = new Button();
            _findNext.Left = 380; _findNext.Top = 12; _findNext.Width = 80; _findNext.Text = "Find Next";
            _findNext.Click += new EventHandler(delegate(object s, EventArgs e)
            {
                if (FindNextClicked != null) FindNextClicked(this, EventArgs.Empty);
            });

            _replace = new Button();
            _replace.Left = 380; _replace.Top = 42; _replace.Width = 80; _replace.Text = "Replace";
            _replace.Click += new EventHandler(delegate(object s, EventArgs e)
            {
                if (ReplaceClicked != null) ReplaceClicked(this, EventArgs.Empty);
            });

            _replaceAll = new Button();
            _replaceAll.Left = 380; _replaceAll.Top = 72; _replaceAll.Width = 80; _replaceAll.Text = "Replace All";
            _replaceAll.Click += new EventHandler(delegate(object s, EventArgs e)
            {
                if (ReplaceAllClicked != null) ReplaceAllClicked(this, EventArgs.Empty);
            });

            Button cancel = new Button();
            cancel.Left = 380; cancel.Top = 102; cancel.Width = 80; cancel.Text = "Cancel";
            cancel.Click += new EventHandler(delegate(object s, EventArgs e) { this.Close(); });

            _find.TextChanged += new EventHandler(delegate(object s, EventArgs e)
            {
                bool ok = (_find.Text != null && _find.Text.Length > 0);
                _findNext.Enabled = ok;
                _replace.Enabled = ok;
                _replaceAll.Enabled = ok;
            });
            {
                bool ok = (_find.Text != null && _find.Text.Length > 0);
                _findNext.Enabled = ok;
                _replace.Enabled = ok;
                _replaceAll.Enabled = ok;
            }

            this.Controls.Add(lf);
            this.Controls.Add(_find);
            this.Controls.Add(lr);
            this.Controls.Add(_repl);
            this.Controls.Add(_matchCase);
            this.Controls.Add(_findNext);
            this.Controls.Add(_replace);
            this.Controls.Add(_replaceAll);
            this.Controls.Add(cancel);

            this.AcceptButton = _findNext;
            this.CancelButton = cancel;
        }
    }

    internal sealed class GoToForm : Form
    {
        private NumericUpDown _n;
        public int LineNumber { get { return (int)_n.Value; } }

        public GoToForm(int maxLine)
        {
            this.Text = "Go To Line";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.CenterParent;
            this.AutoScaleMode = AutoScaleMode.Font;
            this.ClientSize = new Size(300, 120);

            Label l = new Label();
            l.Left = 10; l.Top = 15; l.Width = 90; l.Text = "Line number:";

            _n = new NumericUpDown();
            _n.Left = 110; _n.Top = 12; _n.Width = 170;
            _n.Minimum = 1;
            _n.Maximum = (maxLine < 1) ? 1 : maxLine;
            _n.Value = 1;

            Button ok = new Button();
            ok.Left = 125; ok.Top = 50; ok.Width = 75; ok.Text = "OK";
            ok.DialogResult = DialogResult.OK;

            Button cancel = new Button();
            cancel.Left = 205; cancel.Top = 50; cancel.Width = 75; cancel.Text = "Cancel";
            cancel.DialogResult = DialogResult.Cancel;

            this.AcceptButton = ok;
            this.CancelButton = cancel;

            this.Controls.Add(l);
            this.Controls.Add(_n);
            this.Controls.Add(ok);
            this.Controls.Add(cancel);
        }
    }
}
"@

Add-Type -TypeDefinition $cs -Language CSharp -ReferencedAssemblies @(
    "System.dll",
    "System.Windows.Forms.dll",
    "System.Drawing.dll"
) | Out-Null

$appType = ("$ns.NotepadApp" -as [type])
if (-not $appType) { throw "Failed to locate NotepadApp type." }

$null = $appType::Run([string[]]$args)
