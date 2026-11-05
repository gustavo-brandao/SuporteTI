using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SuporteTI
{
    public sealed class ItemOcupacao
    {
        public string Nome { get; internal set; }
        public string Caminho { get; internal set; }
        public long Bytes { get; internal set; }
        public List<ItemOcupacao> Filhos { get; internal set; }
    }

    public sealed class VarreduraOcupacao
    {
        public ItemOcupacao Raiz { get; private set; }
        public int Ignorados { get; private set; }
        public string Limite { get; private set; }

        private int entradas, maxEntradas, segundos;
        private CancellationToken cancelamento;
        private Stopwatch tempo;

        public static VarreduraOcupacao Ler(string caminho, int maxEntradas, int segundos, CancellationToken cancelamento)
        {
            var resultado = new VarreduraOcupacao {
                maxEntradas = maxEntradas, segundos = segundos, cancelamento = cancelamento, tempo = Stopwatch.StartNew()
            };
            resultado.Raiz = resultado.LerPasta(new DirectoryInfo(caminho), 0);
            return resultado;
        }

        private bool Encerrar()
        {
            if (cancelamento.IsCancellationRequested) Limite = "varredura cancelada";
            else if (entradas >= maxEntradas) Limite = "limite de itens atingido";
            else if (tempo.Elapsed.TotalSeconds >= segundos) Limite = "limite de tempo atingido";
            return Limite != null;
        }

        private ItemOcupacao LerPasta(DirectoryInfo pasta, int profundidade)
        {
            var item = new ItemOcupacao { Nome = pasta.Name, Caminho = pasta.FullName, Filhos = new List<ItemOcupacao>() };
            if (Encerrar()) return item;
            try
            {
                if (profundidade >= 64 || (pasta.Attributes & FileAttributes.ReparsePoint) != 0)
                {
                    Ignorados++;
                    return item;
                }
                foreach (FileSystemInfo entrada in pasta.EnumerateFileSystemInfos())
                {
                    if (Encerrar()) break;
                    entradas++;
                    try
                    {
                        if ((entrada.Attributes & FileAttributes.ReparsePoint) != 0) { Ignorados++; continue; }
                        var subpasta = entrada as DirectoryInfo;
                        var filho = subpasta != null ? LerPasta(subpasta, profundidade + 1) :
                            new ItemOcupacao { Nome = entrada.Name, Caminho = entrada.FullName, Bytes = ((FileInfo)entrada).Length };
                        item.Filhos.Add(filho);
                        item.Bytes += filho.Bytes;
                        if (Limite != null) break;
                    }
                    catch (IOException) { Ignorados++; }
                    catch (UnauthorizedAccessException) { Ignorados++; }
                }
            }
            catch (IOException) { Ignorados++; }
            catch (UnauthorizedAccessException) { Ignorados++; }
            item.Filhos.Sort((a,b) => b.Bytes.CompareTo(a.Bytes));
            return item;
        }
    }

    public sealed class MapaOcupacao : Form
    {
        private static readonly Color[] paleta = {
            Color.SteelBlue, Color.SeaGreen, Color.SlateBlue, Color.DarkGoldenrod,
            Color.Teal, Color.IndianRed, Color.DarkMagenta, Color.SaddleBrown
        };
        private readonly ComboBox unidades = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 95 };
        private readonly Button analisar = new Button { Text = "Analisar", AutoSize = true };
        private readonly Button subir = new Button { Text = "Pasta anterior", AutoSize = true, Enabled = false };
        private readonly Label volume = new Label { Dock = DockStyle.Top, Height = 27, Padding = new Padding(8, 3, 0, 0) };
        private readonly Label estado = new Label { Dock = DockStyle.Top, Height = 30, Padding = new Padding(8, 3, 0, 0), AutoEllipsis = true };
        private readonly Label caminho = new Label { Dock = DockStyle.Bottom, Height = 26, Padding = new Padding(8, 3, 0, 0), AutoEllipsis = true };
        private readonly ListView lista = new ListView { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, MultiSelect = false };
        private readonly PainelMapa desenho = new PainelMapa { Dock = DockStyle.Fill, BackColor = Color.WhiteSmoke };
        private readonly Stack<ItemOcupacao> historico = new Stack<ItemOcupacao>();
        private readonly List<Bloco> blocos = new List<Bloco>();
        private readonly List<Bloco> blocosInternos = new List<Bloco>();
        private ItemOcupacao atual;
        private CancellationTokenSource varredura;

        private sealed class PainelMapa : Panel
        {
            public PainelMapa()
            {
                SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
                ResizeRedraw = true;
            }
        }

        private sealed class Bloco
        {
            public Rectangle Area;
            public ItemOcupacao Item;
        }

        public MapaOcupacao()
        {
            Text = "Suporte TI | Mapa de ocupacao do disco";
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(1040, 620);
            MinimumSize = new Size(700, 420);
            AutoScaleMode = AutoScaleMode.Dpi;
            var topo = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 42, Padding = new Padding(6), WrapContents = false };
            var fechar = new Button { Text = "Voltar ao menu", AutoSize = true };
            topo.Controls.AddRange(new Control[] { new Label { Text = "Unidade", AutoSize = true, Margin = new Padding(3,8,4,0) }, unidades, analisar, subir, fechar });
            lista.Columns.Add("Maiores itens da pasta", 205);
            lista.Columns.Add("Tamanho", 88, HorizontalAlignment.Right);
            var separador = new SplitContainer { Dock = DockStyle.Fill, Width = 1040, SplitterDistance = 730, FixedPanel = FixedPanel.Panel2 };
            separador.Panel1.Controls.Add(desenho);
            separador.Panel2.Controls.Add(lista);
            Controls.Add(separador);
            Controls.Add(caminho);
            Controls.Add(estado);
            Controls.Add(volume);
            Controls.Add(topo);
            fechar.Click += (s,e) => Close();
            CancelButton = fechar;
            analisar.Click += (s,e) => Analisar();
            subir.Click += (s,e) => Exibir(historico.Pop());
            unidades.SelectedIndexChanged += (s,e) => {
                historico.Clear(); Exibir(null); AtualizarVolume(); estado.Text = "Escolha Analisar para criar o mapa.";
            };
            desenho.Paint += (s,e) => Desenhar(e.Graphics);
            desenho.MouseMove += (s,e) => {
                Bloco bloco = blocosInternos.FirstOrDefault(x => x.Area.Contains(e.Location)) ??
                    blocos.FirstOrDefault(x => x.Area.Contains(e.Location));
                caminho.Text = bloco == null ? (atual == null ? "" : atual.Caminho) : Detalhe(bloco.Item);
            };
            desenho.MouseDoubleClick += (s,e) => {
                Bloco bloco = blocos.FirstOrDefault(x => x.Area.Contains(e.Location));
                if (bloco != null) Entrar(bloco.Item);
            };
            lista.DoubleClick += (s,e) => { if (lista.SelectedItems.Count != 0) Entrar((ItemOcupacao)lista.SelectedItems[0].Tag); };
            lista.SelectedIndexChanged += (s,e) => { if (lista.SelectedItems.Count != 0) caminho.Text = Detalhe((ItemOcupacao)lista.SelectedItems[0].Tag); };
            FormClosing += (s,e) => { if (varredura != null) varredura.Cancel(); };
            foreach (DriveInfo drive in DriveInfo.GetDrives())
                if (drive.DriveType == DriveType.Fixed && drive.IsReady) unidades.Items.Add(drive.Name);
            if (unidades.Items.Count != 0) unidades.SelectedIndex = 0;
            else { analisar.Enabled = false; estado.Text = "Nenhuma unidade local disponivel."; }
        }

        private void AtualizarVolume()
        {
            try
            {
                var drive = new DriveInfo((string)unidades.SelectedItem);
                long total = drive.TotalSize, livre = drive.TotalFreeSpace;
                double percentualLivre = total > 0 ? livre * 100.0 / total : 0;
                volume.Text = String.Format("{0}   {1:0.#}% livre / {2:0.#}% usado   |   {3} livres de {4}   |   {5} usados (Windows)",
                    drive.Name, percentualLivre, 100 - percentualLivre, Tamanho(livre), Tamanho(total), Tamanho(total - livre));
            }
            catch (IOException) { volume.Text = "Capacidade da unidade indisponivel."; }
            catch (UnauthorizedAccessException) { volume.Text = "Capacidade da unidade indisponivel."; }
        }

        private async void Analisar()
        {
            if (varredura != null) { varredura.Cancel(); return; }
            var cancelamento = new CancellationTokenSource();
            varredura = cancelamento;
            string unidade = (string)unidades.SelectedItem;
            historico.Clear(); Exibir(null);
            unidades.Enabled = false;
            analisar.Text = "Cancelar";
            estado.Text = "Analisando " + unidade + " ...";
            try
            {
                var resultado = await Task.Run(() => VarreduraOcupacao.Ler(unidade, 350000, 90, cancelamento.Token));
                if (IsDisposed || Disposing) return;
                AtualizarVolume();
                string cobertura = resultado.Limite ?? (resultado.Ignorados == 0 ? "concluida" : "parcial");
                estado.Text = String.Format("Varredura {0} | {1} ignorados ou sem acesso | Mapa: tamanho logico dos arquivos",
                    cobertura, resultado.Ignorados);
                Exibir(resultado.Raiz);
            }
            catch (Exception erro) { if (!IsDisposed) estado.Text = "Falha na varredura: " + erro.Message; }
            finally
            {
                varredura = null;
                cancelamento.Dispose();
                if (!IsDisposed) { unidades.Enabled = true; analisar.Text = "Analisar"; }
            }
        }

        private void Entrar(ItemOcupacao item)
        {
            if (item.Filhos == null || atual == null) return;
            historico.Push(atual);
            Exibir(item);
        }

        private void Exibir(ItemOcupacao item)
        {
            atual = item;
            subir.Enabled = historico.Count != 0;
            caminho.Text = item == null ? "" : item.Caminho;
            lista.BeginUpdate();
            lista.Items.Clear();
            if (item != null)
                foreach (var filho in item.Filhos.Take(100))
                {
                    var linha = new ListViewItem(filho.Nome) { Tag = filho };
                    linha.SubItems.Add(Tamanho(filho.Bytes));
                    lista.Items.Add(linha);
                }
            lista.EndUpdate();
            desenho.Invalidate();
        }

        private static string Tamanho(long bytes)
        {
            return bytes >= 1073741824 ? (bytes / 1073741824.0).ToString("0.##") + " GiB" :
                bytes >= 1048576 ? (bytes / 1048576.0).ToString("0.##") + " MiB" :
                bytes >= 1024 ? (bytes / 1024.0).ToString("0.##") + " KiB" : bytes + " B";
        }

        private static string Detalhe(ItemOcupacao item)
        {
            return (item.Caminho ?? item.Nome) + " | " + Tamanho(item.Bytes);
        }

        private static List<ItemOcupacao> Amostra(ItemOcupacao pasta, int limite)
        {
            var itens = pasta.Filhos.Take(limite).Where(x => x.Bytes > 0).ToList();
            long outros = pasta.Bytes - itens.Sum(x => x.Bytes);
            if (outros > 0) itens.Add(new ItemOcupacao { Nome = "Outros itens", Bytes = outros });
            return itens;
        }

        private static void Dividir(List<ItemOcupacao> itens, int inicio, int fim, Rectangle area, List<Bloco> destino)
        {
            if (inicio >= fim || area.Width <= 0 || area.Height <= 0) return;
            if (fim - inicio == 1) { destino.Add(new Bloco { Area = area, Item = itens[inicio] }); return; }
            long total = 0;
            for (int i = inicio; i < fim; i++) total += itens[i].Bytes;
            long parcial = itens[inicio].Bytes;
            int meio = inicio + 1;
            while (meio < fim - 1 && parcial + itens[meio].Bytes <= total / 2) parcial += itens[meio++].Bytes;
            bool horizontal = area.Width >= area.Height;
            int lado = horizontal ? area.Width : area.Height;
            if (lado < 2) return;
            int corte = Math.Max(1, Math.Min(lado - 1, (int)(lado * (parcial / (double)total))));
            var primeiro = horizontal ? new Rectangle(area.X, area.Y, corte, area.Height) : new Rectangle(area.X, area.Y, area.Width, corte);
            var segundo = horizontal ? new Rectangle(area.X + corte, area.Y, area.Width - corte, area.Height) : new Rectangle(area.X, area.Y + corte, area.Width, area.Height - corte);
            Dividir(itens, inicio, meio, primeiro, destino);
            Dividir(itens, meio, fim, segundo, destino);
        }

        private void Desenhar(Graphics tela)
        {
            blocos.Clear();
            blocosInternos.Clear();
            if (atual == null || atual.Bytes <= 0) return;
            var itens = Amostra(atual, 40);
            Dividir(itens, 0, itens.Count, desenho.ClientRectangle, blocos);
            for (int i = 0; i < blocos.Count; i++)
            {
                Bloco bloco = blocos[i];
                Color cor = paleta[i % paleta.Length];
                using (var pincel = new SolidBrush(cor)) tela.FillRectangle(pincel, bloco.Area);
                var area = bloco.Area;
                if (area.Width < 4 || area.Height < 4) continue;
                tela.DrawRectangle(Pens.White, area.X, area.Y, area.Width - 1, area.Height - 1);
                if (area.Width < 75 || area.Height < 25) continue;
                string texto = bloco.Item.Nome + " | " + Tamanho(bloco.Item.Bytes);
                TextRenderer.DrawText(tela, texto, Font, new Rectangle(area.X + 4, area.Y + 3, area.Width - 8, 18),
                    Color.White, TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                if (bloco.Item.Filhos == null || area.Height < 50) continue;
                var filhos = Amostra(bloco.Item, 12);
                var internos = new List<Bloco>();
                Dividir(filhos, 0, filhos.Count, new Rectangle(area.X + 3, area.Y + 23, area.Width - 6, area.Height - 26), internos);
                foreach (Bloco interno in internos)
                {
                    blocosInternos.Add(interno);
                    using (var pincel = new SolidBrush(ControlPaint.Light(cor))) tela.FillRectangle(pincel, interno.Area);
                    tela.DrawRectangle(Pens.White, interno.Area.X, interno.Area.Y, interno.Area.Width - 1, interno.Area.Height - 1);
                    if (interno.Area.Width >= 62 && interno.Area.Height >= 18)
                        TextRenderer.DrawText(tela, interno.Item.Nome, Font, interno.Area, Color.Black, TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                }
            }
        }
    }
}
