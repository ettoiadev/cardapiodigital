-- Script de otimização da estrutura do banco de dados
-- Alinha a estrutura com o fluxo atual da aplicação

-- 1. ANÁLISE DO FLUXO ATUAL:
-- A aplicação funciona com carrinho local (localStorage) e envio direto via WhatsApp
-- As tabelas de pedidos/clientes existem mas não estão sendo utilizadas no fluxo principal
-- O foco é na mensagem do WhatsApp com informações completas

-- 2. MELHORAR MENSAGEM DO WHATSAPP - Adicionar campos faltantes na mensagem

-- Primeiro, vamos verificar se precisamos adicionar informações sobre sabores na mensagem
-- A mensagem atual não mostra os sabores das pizzas, apenas o nome do produto

-- 3. CAMPOS NÃO UTILIZADOS QUE PODEM SER REMOVIDOS:

-- Tabela 'clientes' - não está sendo usada no fluxo atual
-- Os dados do cliente são coletados apenas para a mensagem do WhatsApp
-- Comentário: Manter por enquanto para futuras funcionalidades

-- Tabela 'pedidos' e 'pedido_itens' - não estão sendo usadas no fluxo atual  
-- Os pedidos são enviados diretamente via WhatsApp sem persistir no banco
-- Comentário: Manter por enquanto para futuras funcionalidades de histórico

-- 4. CAMPOS ÚTEIS MAS NÃO UTILIZADOS:

-- pizzaria_config.foto_capa e foto_perfil - podem ser úteis para interface
-- pizzaria_config.horario_funcionamento - pode ser útil para validações
-- pizzaria_config.aceita_dinheiro e aceita_cartao - podem filtrar opções de pagamento

-- 5. OTIMIZAÇÕES NECESSÁRIAS:

-- A. Melhorar a captura de informações sobre sabores para a mensagem do WhatsApp
-- Atualmente o carrinho tem 'sabores: string[]' mas isso não aparece claramente na mensagem

-- B. Adicionar campos para melhor rastreabilidade (opcional, para futuro):
CREATE TABLE IF NOT EXISTS mensagens_whatsapp (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conteudo_mensagem TEXT NOT NULL,
  numero_whatsapp VARCHAR(20),
  tipo_entrega VARCHAR(20),
  valor_total DECIMAL(10,2),
  data_envio TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  status VARCHAR(50) DEFAULT 'enviado' -- enviado, visualizado, respondido
);

-- C. Índices para melhor performance nas consultas mais comuns:
CREATE INDEX IF NOT EXISTS idx_produtos_categoria_ativo ON produtos(categoria_id, ativo);
CREATE INDEX IF NOT EXISTS idx_produtos_tipo_ativo ON produtos(tipo, ativo);
CREATE INDEX IF NOT EXISTS idx_categorias_ativo_ordem ON categorias(ativo, ordem);
CREATE INDEX IF NOT EXISTS idx_opcoes_sabores_ativo_ordem ON opcoes_sabores(ativo, ordem);

-- D. Adicionar campo para controlar visibilidade de opções de sabores por produto
ALTER TABLE produtos 
ADD COLUMN IF NOT EXISTS permite_multiplos_sabores BOOLEAN DEFAULT true;

-- E. Comentários para documentar o uso das tabelas:
COMMENT ON TABLE pizzaria_config IS 'Configurações gerais da pizzaria - usado ativamente';
COMMENT ON TABLE categorias IS 'Categorias de produtos - usado ativamente no cardápio';
COMMENT ON TABLE produtos IS 'Produtos do cardápio - usado ativamente';
COMMENT ON TABLE opcoes_sabores IS 'Opções de quantidade de sabores - usado ativamente';
COMMENT ON TABLE tamanhos_pizza IS 'Tamanhos de pizza disponíveis - usado no admin';
COMMENT ON TABLE clientes IS 'Dados de clientes - não usado no fluxo atual, reservado para futuro';
COMMENT ON TABLE pedidos IS 'Histórico de pedidos - não usado no fluxo atual, reservado para futuro';
COMMENT ON TABLE pedido_itens IS 'Itens dos pedidos - não usado no fluxo atual, reservado para futuro';
COMMENT ON TABLE mensagens_whatsapp IS 'Log de mensagens enviadas - para rastreabilidade futura';

-- F. Trigger para atualizar updated_at na pizzaria_config
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_pizzaria_config_updated_at 
    BEFORE UPDATE ON pizzaria_config 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- G. Validações importantes
ALTER TABLE produtos 
ADD CONSTRAINT check_preco_positivo 
CHECK (preco_tradicional IS NULL OR preco_tradicional > 0);

ALTER TABLE produtos 
ADD CONSTRAINT check_preco_broto_positivo 
CHECK (preco_broto IS NULL OR preco_broto > 0);

-- H. Dados padrão para facilitar desenvolvimento
UPDATE pizzaria_config 
SET 
  aceita_dinheiro = true,
  aceita_cartao = true,
  horario_funcionamento = '{
    "segunda": {"aberto": true, "abertura": "18:00", "fechamento": "23:00"},
    "terca": {"aberto": true, "abertura": "18:00", "fechamento": "23:00"},
    "quarta": {"aberto": true, "abertura": "18:00", "fechamento": "23:00"},
    "quinta": {"aberto": true, "abertura": "18:00", "fechamento": "23:00"},
    "sexta": {"aberto": true, "abertura": "18:00", "fechamento": "23:30"},
    "sabado": {"aberto": true, "abertura": "18:00", "fechamento": "23:30"},
    "domingo": {"aberto": true, "abertura": "18:00", "fechamento": "23:00"}
  }'::jsonb
WHERE horario_funcionamento IS NULL;

-- I. Limpeza de dados inconsistentes (se houver)
-- Remover produtos órfãos (sem categoria) se não forem bebidas
UPDATE produtos 
SET categoria_id = (SELECT id FROM categorias WHERE nome = 'Bebidas' LIMIT 1)
WHERE categoria_id IS NULL AND tipo = 'bebida';

-- J. Verificação final da integridade
DO $$
DECLARE
    produtos_sem_categoria INTEGER;
    categorias_inativas_com_produtos INTEGER;
BEGIN
    -- Verificar produtos sem categoria
    SELECT COUNT(*) INTO produtos_sem_categoria 
    FROM produtos 
    WHERE categoria_id IS NULL AND ativo = true;
    
    IF produtos_sem_categoria > 0 THEN
        RAISE WARNING 'Existem % produtos ativos sem categoria', produtos_sem_categoria;
    END IF;
    
    -- Verificar categorias inativas com produtos ativos
    SELECT COUNT(DISTINCT p.categoria_id) INTO categorias_inativas_com_produtos
    FROM produtos p
    JOIN categorias c ON p.categoria_id = c.id
    WHERE p.ativo = true AND c.ativo = false;
    
    IF categorias_inativas_com_produtos > 0 THEN
        RAISE WARNING 'Existem produtos ativos em categorias inativas';
    END IF;
    
    RAISE NOTICE 'Verificação de integridade concluída';
END $$;

-- K. Estatísticas finais
SELECT 
    'Resumo da Estrutura Otimizada' as status,
    (SELECT COUNT(*) FROM categorias WHERE ativo = true) as categorias_ativas,
    (SELECT COUNT(*) FROM produtos WHERE ativo = true) as produtos_ativos,
    (SELECT COUNT(*) FROM opcoes_sabores WHERE ativo = true) as opcoes_sabores_ativas,
    (SELECT COUNT(*) FROM tamanhos_pizza WHERE ativo = true) as tamanhos_ativos;
