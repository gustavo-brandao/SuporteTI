using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security;

namespace SuporteTI
{
    public static class LogonNativo
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LsaString
        {
            public ushort Length, MaximumLength;
            public IntPtr Buffer;

            public LsaString(IntPtr buffer, int characters)
            {
                Length = checked((ushort)(characters * 2));
                MaximumLength = checked((ushort)(Length + 2));
                Buffer = buffer;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LsaAttributes
        {
            public uint Length;
            public IntPtr RootDirectory, ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor, SecurityQualityOfService;
        }

        [DllImport("advapi32.dll")]
        private static extern uint LsaOpenPolicy(IntPtr systemName, ref LsaAttributes attributes, uint access, out IntPtr handle);

        [DllImport("advapi32.dll")]
        private static extern uint LsaStorePrivateData(IntPtr policy, ref LsaString name, IntPtr data);

        [DllImport("advapi32.dll")]
        private static extern uint LsaNtStatusToWinError(uint status);

        [DllImport("advapi32.dll")]
        private static extern uint LsaClose(IntPtr handle);

        public static void GravarSenha(SecureString senha)
        {
            if (senha == null || senha.Length == 0 || senha.Length > 256)
                throw new ArgumentException("Informe uma senha de 1 a 256 caracteres.");
            AlterarSegredo(senha);
        }

        public static void RemoverSenha()
        {
            AlterarSegredo(null);
        }

        private static void AlterarSegredo(SecureString senha)
        {
            const uint criarSegredo = 0x20;
            const uint objetoAusente = 0xC0000034;
            const string nome = "DefaultPassword";
            var atributos = new LsaAttributes();
            IntPtr politica = IntPtr.Zero, chave = IntPtr.Zero, caracteres = IntPtr.Zero, dados = IntPtr.Zero;
            try
            {
                uint status = LsaOpenPolicy(IntPtr.Zero, ref atributos, criarSegredo, out politica);
                if (status != 0) throw new Win32Exception((int)LsaNtStatusToWinError(status));
                chave = Marshal.StringToHGlobalUni(nome);
                var chaveLsa = new LsaString(chave, nome.Length);
                if (senha != null)
                {
                    caracteres = Marshal.SecureStringToGlobalAllocUnicode(senha);
                    dados = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LsaString)));
                    Marshal.StructureToPtr(new LsaString(caracteres, senha.Length), dados, false);
                }
                status = LsaStorePrivateData(politica, ref chaveLsa, dados);
                if (status != 0 && !(senha == null && status == objetoAusente))
                    throw new Win32Exception((int)LsaNtStatusToWinError(status));
            }
            finally
            {
                if (dados != IntPtr.Zero) Marshal.FreeHGlobal(dados);
                if (caracteres != IntPtr.Zero) Marshal.ZeroFreeGlobalAllocUnicode(caracteres);
                if (chave != IntPtr.Zero) Marshal.FreeHGlobal(chave);
                if (politica != IntPtr.Zero) LsaClose(politica);
            }
        }
    }
}
