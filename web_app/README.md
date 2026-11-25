# Teste Movimento Web

Versão de testes do protocolo de avaliação de mobilidade para navegador. Em **Iniciar com câmera**, permita o acesso e mantenha o corpo inteiro no quadro. Realize três abduções frontais e, em seguida, três agachamentos com o lado direito voltado para a câmera. **Testar demonstração** percorre as duas etapas com coordenadas simuladas.

A avaliação mede os ângulos no plano da imagem e registra as articulações no pico de cada repetição. A geometria web pode produzir valores diferentes dos filtros e estimativas do aplicativo Android. Histórico e CSV identificam a origem da sessão. Fechar uma sessão incompleta descarta suas repetições. O histórico é específico do navegador e do endereço usado para abrir o app.

## Desenvolvimento local

Com Node.js 22.12+ e npm, execute nesta pasta:

```sh
npm ci
npm run dev
```

Abra o endereço localhost exibido pelo Vite. Para testar no celular, abra o endereço HTTPS da Vercel e autorize a câmera. Os arquivos do MediaPipe e o modelo são servidos pelo próprio site.

## Vercel

Ao importar o repositório, selecione **web_app** como Root Directory, **Vite** como framework, **npm run build** como Build Command e **dist** como Output Directory. Inclua o modelo public/pose_landmarker_lite.task no commit. O script prebuild copia o runtime WebAssembly da dependência fixada no lockfile.

Com a CLI autenticada, também é possível publicar a partir desta pasta com `vercel --prod`.
