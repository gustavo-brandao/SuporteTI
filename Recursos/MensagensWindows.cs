using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace SuporteTI
{
    public static class MensagensWindows
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string nome);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern int FormatMessage(uint flags, IntPtr origem, uint codigo, uint idioma,
            StringBuilder mensagem, int capacidade, IntPtr argumentos);

        public static string Ler(uint codigo, bool ntstatus)
        {
            const uint ignorarParametros = 0x200;
            const uint doModulo = 0x800;
            const uint doSistema = 0x1000;
            const uint portuguesBrasil = 0x0416;
            IntPtr origem = ntstatus ? GetModuleHandle("ntdll.dll") : IntPtr.Zero;
            if (ntstatus && origem == IntPtr.Zero) return null;

            var mensagem = new StringBuilder(2048);
            uint flags = ignorarParametros | (ntstatus ? doModulo : doSistema);
            if (FormatMessage(flags, origem, codigo, portuguesBrasil, mensagem, mensagem.Capacity, IntPtr.Zero) == 0)
                return null;

            string texto = Regex.Replace(mensagem.ToString(), @"%(?:[1-9][0-9]*(?:![^!]*!)?|[lhw]?[sduxXp])", "[dado do evento]");
            texto = Regex.Replace(texto, @"\s+", " ").Trim();
            return texto.Length <= 420 ? texto : texto.Substring(0, 417) + "...";
        }
    }
}
